#!/usr/bin/env python3
"""Signal classifier daemon — listens to Redis pub/sub, classifies signals in background.

Usage:
  python3 scripts/map_signals_daemon.py [--daemon]

Listens to channel:signal:new, classifies each signal via map_and_save_signal(),
publishes channel:signal:mapped when done.
Runs independently from the parser daemon — non-blocking, continuous.
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
import signal as signal_module
import sys
from typing import Optional

# Ensure app is importable
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger("map_signals_daemon")


class SignalMapperDaemon:
    """Listens to Redis pub/sub and classifies signals in background."""

    def __init__(self):
        from app.core.config import settings
        self.redis_url = settings.REDIS_URL
        self._running = True
        self._semaphore = asyncio.Semaphore(5)  # Max 5 concurrent classifications

    async def _process_signal(self, data: dict):
        """Classify a single signal with concurrency control."""
        signal_id = data.get("id")
        pair = data.get("pair", "???")

        if not signal_id:
            logger.warning("Signal data missing 'id', skipping")
            return

        async with self._semaphore:
            try:
                from app.core.database import async_session_factory
                from app.services.signals.signal_mapper import map_and_save_signal

                async with async_session_factory() as session:
                    result = await map_and_save_signal(session, signal_id)

                if result:
                    logger.info(
                        "Mapped signal #%d (%s): %s → %s/%s (conf=%.2f)",
                        signal_id, pair,
                        result.signal_label,
                        result.mapped_engine, result.mapped_strategy,
                        result.confidence,
                    )
                else:
                    logger.warning("Mapping returned None for signal #%d (%s)", signal_id, pair)
            except Exception as e:
                logger.error("Failed to map signal #%d (%s): %s", signal_id, pair, e, exc_info=True)

    async def run_forever(self):
        """Main loop: subscribe to Redis and process signals forever."""
        logger.info("SignalMapperDaemon starting...")

        while self._running:
            from redis.asyncio import Redis as AsyncRedis

            r = AsyncRedis.from_url(self.redis_url, encoding="utf-8", decode_responses=True)
            pubsub = r.pubsub()

            try:
                await pubsub.subscribe("channel:signal:new")
                logger.info("Subscribed to channel:signal:new")

                while self._running:
                    try:
                        message = await pubsub.get_message(timeout=1.0, ignore_subscribe_messages=True)
                    except asyncio.TimeoutError:
                        continue
                    except Exception as e:
                        logger.warning("get_message error: %s", e, exc_info=True)
                        await asyncio.sleep(1)
                        continue

                    if message is None:
                        continue

                    try:
                        data = json.loads(message["data"])
                    except (json.JSONDecodeError, KeyError):
                        continue

                    pair = data.get("pair", "???")
                    logger.info("Received signal: #%d %s — starting classification", data.get("id"), pair)

                    # Fire-and-forget with concurrency semaphore
                    asyncio.create_task(self._process_signal(data))

            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.warning("Redis error: %s — reconnecting in 3s", e, exc_info=True)
                await asyncio.sleep(3)
            finally:
                await pubsub.unsubscribe()
                await r.aclose()

        logger.info("SignalMapperDaemon stopped")

    def stop(self):
        self._running = False


def run():
    daemon = SignalMapperDaemon()

    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)

    def _stop():
        logger.info("Shutting down SignalMapperDaemon...")
        daemon.stop()

    for sig in (signal_module.SIGINT, signal_module.SIGTERM):
        try:
            loop.add_signal_handler(sig, _stop)
        except (NotImplementedError, ValueError):
            pass

    try:
        loop.run_until_complete(daemon.run_forever())
    except KeyboardInterrupt:
        pass
    finally:
        loop.close()


if __name__ == "__main__":
    run()
