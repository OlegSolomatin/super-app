#!/usr/bin/env python3
"""Telegram screener signal parser.

Usage:
  python3 scripts/parse_telegram_signals.py          # one-shot (cron mode)
  python3 scripts/parse_telegram_signals.py --daemon # continuous loop

One-shot: fetches channels, saves + classifies signals, exits.
Daemon:   loops every 30s, same logic, never exits.
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
import sys
from datetime import datetime, timezone

# Ensure app is importable
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger("parse_telegram_signals")

# ── Database ────────────────────────────────────────────────────────────────


async def save_signals(signals) -> list[int]:
    """Save parsed signals to database and Redis cache.

    Returns list of new signal IDs.
    """
    from app.core.cache import publish, set_cache
    from app.core.database import async_session_factory
    from app.models.trading_signal import TradingSignal

    new_ids: list[int] = []
    skipped_dedup = 0      # duplicate within 30 min window
    skipped_duplicate = 0  # older duplicate (will save anyway? no — just count)

    async with async_session_factory() as session:
        for sig in signals:
            from sqlalchemy import select

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
            new_ids.append(signal.id)

        if new_ids:
            await session.commit()
            logger.info("Saved %d new signals: %s", len(new_ids), new_ids)

        # ── Cleanup: keep max 200 signals ────────────────
        try:
            from sqlalchemy import func as sa_func, select as sa_select, delete as sa_delete

            count_stmt = sa_select(sa_func.count(TradingSignal.id))
            count_result = await session.execute(count_stmt)
            total = count_result.scalar() or 0

            if total > 200:
                to_delete = total - 200
                # Find oldest N signal IDs to delete
                oldest_stmt = (
                    sa_select(TradingSignal.id)
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
                        "Cleanup: removed %d old signal(s) (total was %d, max 200): IDs %s",
                        len(oldest_ids), total, oldest_ids,
                    )
        except Exception as e:
            logger.warning("Signal cleanup failed (non-fatal): %s", e)

    # Cache in Redis (optional — falls back gracefully if Redis is down)
    try:
        for sig in signals:
            key = f"signal:raw:{sig.channel}:{sig.pair}"
            await set_cache(
                key,
                {
                    "channel": sig.channel,
                    "exchange": sig.exchange,
                    "pair": sig.pair,
                    "price_range": sig.price_range,
                    "vol_60m": sig.vol_60m,
                    "vol_10m": sig.vol_10m,
                    "slope": sig.slope,
                    "top_ratio": sig.top_ratio,
                    "bot_ratio": sig.bot_ratio,
                },
                ttl=604800,  # 7 days
            )
    except Exception as e:
        logger.warning("Redis cache unavailable (skip): %s", e)

    # Publish new signals to real-time frontend
    for sid in new_ids:
        try:
            async with async_session_factory() as s:
                from sqlalchemy import select

                stmt = select(TradingSignal).where(TradingSignal.id == sid)
                result = await s.execute(stmt)
                db_signal = result.scalar_one_or_none()
                if db_signal:
                    await publish(
                        "channel:signal:new",
                    {
                        "id": db_signal.id,
                        "channel": db_signal.channel,
                        "exchange": db_signal.exchange,
                        "pair": db_signal.pair,
                        "price_range": db_signal.price_range,
                        "vol_60m": db_signal.vol_60m,
                        "vol_10m": db_signal.vol_10m,
                        "slope": db_signal.slope,
                        "top_ratio": db_signal.top_ratio,
                        "bot_ratio": db_signal.bot_ratio,
                        "created_at": db_signal.created_at.isoformat() if db_signal.created_at else None,
                    },
                )
                logger.info("Published signal #%d to Redis pub/sub", sid)
        except Exception as e:
            logger.warning("Redis pub/sub unavailable (skip signal #%d): %s", sid, e)

    # Populate signals:latest list in Redis (for live endpoint)
    if new_ids:
        try:
            from redis.asyncio import Redis as AsyncRedis
            from app.core.config import settings

            r = AsyncRedis.from_url(
                settings.REDIS_URL, encoding="utf-8", decode_responses=True
            )
            try:
                for sid in new_ids:
                    async with async_session_factory() as s:
                        stmt = select(TradingSignal).where(TradingSignal.id == sid)
                        result = await s.execute(stmt)
                        db_signal = result.scalar_one_or_none()
                        if db_signal:
                            signal_dict = {
                                "id": db_signal.id,
                                "channel": db_signal.channel,
                                "exchange": db_signal.exchange,
                                "pair": db_signal.pair,
                                "price_range": db_signal.price_range,
                                "vol_60m": db_signal.vol_60m,
                                "vol_10m": db_signal.vol_10m,
                                "slope": db_signal.slope,
                                "top_ratio": db_signal.top_ratio,
                                "bot_ratio": db_signal.bot_ratio,
                                "mapped_strategy": db_signal.mapped_strategy,
                                "mapped_engine": db_signal.mapped_engine,
                                "mapped_exchange_fallback": db_signal.mapped_exchange_fallback,
                                "mapped_available_exchanges": db_signal.mapped_available_exchanges,
                                "created_at": db_signal.created_at.isoformat() if db_signal.created_at else None,
                            }
                            await r.lpush("signals:latest", json.dumps(signal_dict))
                # Keep only latest 50 in the list
                await r.ltrim("signals:latest", 0, 49)
                logger.info("Updated signals:latest list (%d new, trimmed to 50)", len(new_ids))
            finally:
                await r.aclose()
        except Exception as e:
            logger.warning("Failed to update signals:latest: %s", e)

    return new_ids


# ── Main ────────────────────────────────────────────────────────────────────


async def main():
    from app.services.signals.telegram_parser import parse_all_channels

    logger.info("Parsing Telegram screener channels...")
    signals = await parse_all_channels()
    logger.info("Found %d raw signals", len(signals))

    if not signals:
        logger.info("No signals found from Telegram channels")
        return

    new_ids = await save_signals(signals)

    # Map new signals (classify + cross-exchange lookup) — IN PARALLEL
    if new_ids:
        from app.services.signals.signal_mapper import map_and_save_signal
        from app.core.database import async_session_factory

        async def _map_one(sid: int):
            try:
                async with async_session_factory() as session:
                    await map_and_save_signal(session, sid)
                logger.info("Mapped signal #%d", sid)
            except Exception as e:
                logger.warning("Failed to map signal #%d: %s", sid, e)

        await asyncio.gather(*[_map_one(sid) for sid in new_ids])
        logger.info("All %d signal(s) mapped in parallel", len(new_ids))

    # ── User-facing output ────────────────────────────────────────────────
    total = len(signals)
    skipped = total - len(new_ids)

    if new_ids:
        # Fetch details for notification
        from app.core.database import async_session_factory as asf2
        from app.models.trading_signal import TradingSignal
        from sqlalchemy import select

        lines = [f"🔥 *Новые сигналы ({len(new_ids)})*"]
        async with asf2() as session:
            for sid in new_ids:
                stmt = select(TradingSignal).where(TradingSignal.id == sid)
                r = await session.execute(stmt)
                s = r.scalar_one_or_none()
                if s:
                    lines.append(
                        f"• #{s.id} {s.pair} @ {s.channel} — "
                        f"range={s.price_range}, vol10m={s.vol_10m}"
                    )
        lines.append("")
        lines.append(f"Пропущено (дубликаты <30м): {skipped}")
        print("\n".join(lines))
    else:
        print(f"⏸ Новых сигналов нет. Найдено {total}, пропущено {skipped} (дубликаты <30 мин)")

    logger.info("Done — saved %d new signals (skipped %d duplicates)", len(new_ids), skipped)


async def run_daemon():
    """Run parser in continuous loop — polls every 30 seconds."""
    import signal as signal_module

    logger.info("Signal parser daemon starting (poll interval=30s)...")

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
        # Sleep 30s between cycles (check running flag every second)
        for _ in range(30):
            if not running:
                break
            await asyncio.sleep(1)

    logger.info("Signal parser daemon stopped")


if __name__ == "__main__":
    import sys

    if "--daemon" in sys.argv:
        asyncio.run(run_daemon())
    else:
        asyncio.run(main())
