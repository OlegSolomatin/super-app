#!/usr/bin/env python3
"""Telegram screener signal parser — fast, non-blocking.

Usage:
  python3 scripts/parse_telegram_signals.py          # one-shot
  python3 scripts/parse_telegram_signals.py --daemon # continuous loop (recommended)

One-shot: fetches channels, saves + publishes raw signals, exits.
Daemon:   loops every 15s, same logic, never exits.
Classification is handled by a separate map_signals_daemon.py.
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
import sys
from datetime import datetime, timezone
from typing import Optional

import httpx

# Ensure app is importable
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger("parse_telegram_signals")

# ── Reusable connections (module-level, survive across cycles) ────────────
_redis_client: Optional = None
_http_client: Optional[httpx.AsyncClient] = None


def _get_http_client() -> httpx.AsyncClient:
    global _http_client
    if _http_client is None or _http_client.is_closed:
        _http_client = httpx.AsyncClient(
            timeout=15,
            headers={"User-Agent": "Mozilla/5.0"},
        )
    return _http_client


async def _get_redis():
    """Get or create reusable Redis connection."""
    global _redis_client
    if _redis_client is None:
        from redis.asyncio import Redis as AsyncRedis
        from app.core.config import settings
        _redis_client = AsyncRedis.from_url(
            settings.REDIS_URL, encoding="utf-8", decode_responses=True
        )
        logger.info("Created reusable Redis connection")
    try:
        await _redis_client.ping()
    except Exception:
        from redis.asyncio import Redis as AsyncRedis
        from app.core.config import settings
        _redis_client = AsyncRedis.from_url(
            settings.REDIS_URL, encoding="utf-8", decode_responses=True
        )
    return _redis_client


# ── Database ────────────────────────────────────────────────────────────────


async def save_signals(signals) -> list[dict]:
    """Save parsed signals to database and Redis.

    Returns list of signal dicts (id, pair, channel, exchange, raw_data, created_at).
    Uses in-memory data only — no re-fetching from DB.
    """
    from app.core.cache import publish
    from app.core.database import async_session_factory
    from app.models.trading_signal import TradingSignal
    from sqlalchemy import select, func as sa_func, delete as sa_delete

    async with async_session_factory() as session:
        new_signals: list[dict] = []
        skipped_dedup = 0

        for sig in signals:
            stmt = (
                select(TradingSignal)
                .where(
                    TradingSignal.pair == sig.pair,
                    TradingSignal.channel == sig.channel,
                )
                .order_by(TradingSignal.created_at.desc())
                .limit(1)
            )
            result = await session.execute(stmt)
            existing = result.scalar_one_or_none()

            if existing and existing.created_at:
                age_sec = (datetime.now(timezone.utc) - existing.created_at).total_seconds()
                if age_sec < 1800:
                    skipped_dedup += 1
                    continue

            signal = TradingSignal(
                channel=sig.channel,
                exchange=sig.exchange,
                pair=sig.pair,
                price_range=sig.price_range,
                vol_60m=sig.vol_60m,
                vol_10m=sig.vol_10m,
                slope=sig.slope,
                top_ratio=sig.top_ratio,
                bot_ratio=sig.bot_ratio,
            )
            session.add(signal)
            await session.flush()

            new_signals.append({
                "id": signal.id,
                "channel": signal.channel,
                "exchange": signal.exchange,
                "pair": signal.pair,
                "price_range": signal.price_range,
                "vol_60m": signal.vol_60m,
                "vol_10m": signal.vol_10m,
                "slope": signal.slope,
                "top_ratio": signal.top_ratio,
                "bot_ratio": signal.bot_ratio,
                "created_at": datetime.now(timezone.utc).isoformat(),
            })

        if new_signals:
            await session.commit()
            logger.info("Saved %d new signals: %s", len(new_signals), [s["id"] for s in new_signals])

        # ── Cleanup: keep max 200 signals ────────────────
        try:
            count_stmt = select(sa_func.count(TradingSignal.id))
            count_result = await session.execute(count_stmt)
            total = count_result.scalar() or 0

            if total > 200:
                to_delete = total - 200
                oldest_stmt = (
                    select(TradingSignal.id)
                    .order_by(TradingSignal.created_at.asc())
                    .limit(to_delete)
                )
                oldest_result = await session.execute(oldest_stmt)
                oldest_ids = [row[0] for row in oldest_result.fetchall()]

                if oldest_ids:
                    delete_stmt = sa_delete(TradingSignal).where(TradingSignal.id.in_(oldest_ids))
                    await session.execute(delete_stmt)
                    await session.commit()
                    logger.info(
                        "Cleanup: removed %d old signal(s) (total was %d)",
                        len(oldest_ids), total,
                    )
        except Exception as e:
            logger.warning("Signal cleanup failed (non-fatal): %s", e)

    if not new_signals:
        return []

    # ── Redis operations (reuse connection) ──────────────────────────────
    r = await _get_redis()

    for sd in new_signals:
        sig_dict = {
            "id": sd["id"],
            "channel": sd["channel"],
            "exchange": sd["exchange"],
            "pair": sd["pair"],
            "price_range": sd["price_range"],
            "vol_60m": sd["vol_60m"],
            "vol_10m": sd["vol_10m"],
            "slope": sd["slope"],
            "top_ratio": sd["top_ratio"],
            "bot_ratio": sd["bot_ratio"],
            "created_at": sd["created_at"],
            "mapped_strategy": None,
            "mapped_engine": None,
        }

        # Cache raw signal (7 days TTL)
        cache_key = f"signal:raw:{sd['channel']}:{sd['pair']}"
        await r.setex(cache_key, 604800, json.dumps(sig_dict))

        # Push to signals:latest
        await r.lpush("signals:latest", json.dumps(sig_dict))

        # Publish to Redis pub/sub (for notification bot + mapper daemon)
        try:
            await publish("channel:signal:new", sig_dict)
        except Exception as e:
            logger.warning("Redis pub/sub unavailable (skip publish #%d): %s", sd["id"], e)

    await r.ltrim("signals:latest", 0, 49)
    logger.info("Redis updated: %d signals pushed, trimmed to 50", len(new_signals))

    return new_signals


# ── Main ────────────────────────────────────────────────────────────────────


async def main():
    """One cycle: fetch channels → save → exit."""
    from app.services.signals.telegram_parser import parse_all_channels

    logger.info("Parsing Telegram screener channels...")
    signals = await parse_all_channels()
    logger.info("Found %d raw signals", len(signals))

    if not signals:
        logger.info("No signals found from Telegram channels")
        print("⏸ Новых сигналов нет")
        return

    new_signal_dicts = await save_signals(signals)

    new_ids = [s["id"] for s in new_signal_dicts]
    total = len(signals)
    skipped = total - len(new_ids)

    if new_ids:
        lines = [f"🔥 *Новые сигналы ({len(new_ids)})*"]
        for sd in new_signal_dicts:
            lines.append(
                f"• #{sd['id']} {sd['pair']} @ {sd['channel']} — "
                f"range={sd['price_range']}, vol10m={sd['vol_10m']}"
            )
        lines.append("")
        lines.append(f"Пропущено (дубликаты <30м): {skipped}")
        print("\n".join(lines))
    else:
        print(f"⏸ Новых сигналов нет. Найдено {total}, пропущено {skipped}")

    logger.info("Done — saved %d new signals (skipped %d)", len(new_ids), skipped)


async def run_daemon():
    """Run parser in continuous loop — polls every 15 seconds."""
    import signal as signal_module

    logger.info("Signal parser daemon starting (poll interval=15s)...")

    running = True

    def _stop():
        nonlocal running
        running = False
        logger.info("Shutting down signal parser daemon...")

    for sig in (signal_module.SIGINT, signal_module.SIGTERM):
        try:
            loop = asyncio.get_event_loop()
            loop.add_signal_handler(sig, _stop)
        except (NotImplementedError, ValueError):
            pass

    while running:
        try:
            await main()
        except Exception as e:
            logger.error("Parser cycle failed: %s", e, exc_info=True)
        for _ in range(15):
            if not running:
                break
            await asyncio.sleep(1)

    # Clean up connections
    global _redis_client, _http_client
    if _redis_client:
        try:
            await _redis_client.aclose()
        except Exception:
            pass
        _redis_client = None
    if _http_client and not _http_client.is_closed:
        await _http_client.aclose()
        _http_client = None

    logger.info("Signal parser daemon stopped")


if __name__ == "__main__":
    if "--daemon" in sys.argv:
        asyncio.run(run_daemon())
    else:
        asyncio.run(main())
