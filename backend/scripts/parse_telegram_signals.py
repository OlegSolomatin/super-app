#!/usr/bin/env python3
"""Telegram screener signal parser — fast, non-blocking, message_id dedup.

Usage:
  python3 scripts/parse_telegram_signals.py          # one-shot
  python3 scripts/parse_telegram_signals.py --daemon # continuous loop (recommended)

One-shot: fetches channels, saves + publishes raw signals, exits.
Daemon:   loops every 15s, same logic, never exits.
Classification is handled by a separate map_signals_daemon.py.

Dedup: uses Telegram post IDs (data-post="channel/12345") stored in Redis.
Only processes messages with IDs higher than the last seen one per channel.
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
import sys
import time
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


def _parse_numeric_id(post_id: str) -> int:
    """Extract numeric ID from 'brushscreener/497075' → 497075."""
    try:
        return int(post_id.split("/")[-1])
    except (ValueError, IndexError):
        return 0


# ── Database ────────────────────────────────────────────────────────────────


async def save_signals(signals) -> list[dict]:
    """Save parsed signals to database and Redis.

    Dedup by message_id (Telegram post ID) via Redis.
    Only saves signals with ID > last_seen for their channel.

    Returns list of new signal dicts.
    """
    from app.core.cache import publish
    from app.core.database import async_session_factory
    from app.models.trading_signal import TradingSignal
    from sqlalchemy import select, func as sa_func, delete as sa_delete

    if not signals:
        return []

    t_start = time.monotonic()

    # ── Group signals by channel, get last_seen IDs from Redis ──────────
    r = await _get_redis()

    by_channel: dict[str, list] = {}
    for sig in signals:
        by_channel.setdefault(sig.channel, []).append(sig)

    filtered_signals = []
    channel_max_ids: dict[str, int] = {}  # channel -> max numeric ID in this batch

    for channel, chan_signals in by_channel.items():
        # Get last seen post ID from Redis
        redis_key = f"signal:channel:last_id:{channel}"
        last_post_id = await r.get(redis_key)
        last_numeric = _parse_numeric_id(last_post_id) if last_post_id else 0

        logger.info(
            "Channel %s: last_seen_id=%s (%d), checking %d signals",
            channel, last_post_id or "none", last_numeric, len(chan_signals),
        )

        for sig in chan_signals:
            sig_numeric = _parse_numeric_id(sig.message_id)
            if sig_numeric == 0:
                logger.warning("Signal has invalid message_id='%s', skipping", sig.message_id)
                continue
            if sig_numeric <= last_numeric:
                continue
            filtered_signals.append(sig)
            # Track max per channel
            if channel not in channel_max_ids or sig_numeric > channel_max_ids[channel]:
                channel_max_ids[channel] = sig_numeric

    if not filtered_signals:
        logger.info("No new signals after message_id dedup")
        return []

    logger.info(
        "After message_id dedup: %d new signal(s) from %s",
        len(filtered_signals),
        ", ".join(f"{ch}:{channel_max_ids[ch]}" for ch in channel_max_ids),
    )

    # ── Save to DB ──────────────────────────────────────────────────────
    new_signals: list[dict] = []

    async with async_session_factory() as session:
        for sig in filtered_signals:
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

    # ── Update last_seen IDs in Redis ───────────────────────────────────
    for channel, max_id in channel_max_ids.items():
        post_key = f"signal:channel:last_id:{channel}"
        # Build the post ID string: "channelname/507075"
        post_id_str = f"{channel}/{max_id}"
        await r.set(post_key, post_id_str)
        logger.info("Updated last_seed_id for %s → %s", channel, post_id_str)

    # ── Push to Redis lists + pub/sub ────────────────────────────────────
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
        await r.set(cache_key, json.dumps(sig_dict), ex=604800)

        # Push to signals:latest
        await r.lpush("signals:latest", json.dumps(sig_dict))

        # Publish to Redis pub/sub (for notification bot + mapper daemon)
        try:
            await publish("channel:signal:new", sig_dict)
        except Exception as e:
            logger.warning("Redis pub/sub unavailable (skip publish #%d): %s", sd["id"], e)

    await r.ltrim("signals:latest", 0, 49)

    # Timing
    t_end = time.monotonic()
    for sd in new_signals:
        logger.info(
            "Signal #%d (%s): parse→publish in %.0fms",
            sd["id"], sd["pair"], (t_end - t_start) * 1000,
        )

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
        lines.append(f"Пропущено (дубликаты): {skipped}")
        print("\n".join(lines))
    else:
        print(f"⏸ Новых сигналов нет. Найдено {total}, пропущено {skipped}")

    logger.info("Done — saved %d new signals (skipped %d)", len(new_ids), skipped)


async def run_daemon():
    """Run parser in continuous loop - polls every 5 seconds."""
    import signal as signal_module

    logger.info("Signal parser daemon starting (poll interval=5s)...")

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
        for _ in range(5):
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
