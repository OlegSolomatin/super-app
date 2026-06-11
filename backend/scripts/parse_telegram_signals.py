#!/usr/bin/env python3
"""Cronjob: parse Telegram screener channels and persist signals.

Runs every 3 minutes. Fetches @brushscreener and @stairscreener,
parses signals, saves to DB and caches in Redis.
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

    new_ids = []
    async with async_session_factory() as session:
        for sig in signals:
            # Check if this signal already exists (same pair + channel + recent)
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

            if existing:
                # Skip if we already have this signal recently (within 30 min)
                if existing.created_at and (
                    datetime.now(timezone.utc) - existing.created_at
                ).total_seconds() < 1800:
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

    return new_ids


# ── Main ────────────────────────────────────────────────────────────────────


async def main():
    from app.services.signals.telegram_parser import parse_all_channels

    logger.info("Parsing Telegram screener channels...")
    signals = await parse_all_channels()
    logger.info("Found %d raw signals", len(signals))

    if not signals:
        logger.info("No new signals found")
        return

    new_ids = await save_signals(signals)

    if new_ids:
        print(f"NEW_SIGNALS:{':'.join(str(i) for i in new_ids)}")
    logger.info("Done — saved %d new signals", len(new_ids))


if __name__ == "__main__":
    asyncio.run(main())
