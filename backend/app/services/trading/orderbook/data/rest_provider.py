"""REST-based OrderBook data provider — polls any exchange's REST API.

Works with any exchange that has a REST order book endpoint via the
AbstractExchange interface (including CCXTExchange for 100+ exchanges).

Unlike the WS-based providers (BinanceDataProvider, BybitDataProvider),
this polls the REST API every N seconds. It's slower but works universally.

Architecture:
  - Wraps an AbstractExchange instance
  - Polls get_orderbook() every POLL_INTERVAL seconds
  - Converts the response to OrderBookSnapshot
  - Calls the callback (same as WS providers)

Trade-offs vs WS:
  + Works with ANY exchange (no need for WS support)
  + Simpler, no reconnection logic needed (each request is independent)
  - Slower: 1-2s interval vs 100ms WS
  - Higher API rate limit usage
  - No real-time streaming
"""

from __future__ import annotations

import asyncio
import logging
from datetime import datetime, timezone
from typing import Any, Callable, Coroutine, Optional

from app.services.trading.exchange.base import AbstractExchange
from app.services.trading.orderbook.data.base import DataProvider
from app.services.trading.orderbook.models import OrderBookSnapshot

logger = logging.getLogger(__name__)

# How often to poll the order book (seconds)
POLL_INTERVAL = 1.5


class RestOrderBookProvider(DataProvider):
    """OrderBook data provider that polls a REST API.

    Works with any exchange that implements AbstractExchange.get_orderbook().
    Each pair is polled independently every POLL_INTERVAL seconds.

    Usage:
        exchange = CCXTExchange(exchange_name="mexc")
        provider = RestOrderBookProvider(
            pairs=["BTCUSDT", "ETHUSDT"],
            exchange=exchange,
        )
        await provider.start(on_snapshot)
    """

    def __init__(
        self,
        pairs: list[str],
        exchange: AbstractExchange,
        poll_interval: float = POLL_INTERVAL,
    ) -> None:
        super().__init__(pairs)
        self._exchange = exchange
        self._poll_interval = poll_interval
        self._tasks: list[asyncio.Task] = []

    @property
    def name(self) -> str:
        return self._exchange.name

    async def start(
        self,
        callback: Callable[[OrderBookSnapshot],
                           Coroutine[Any, Any, None]],
    ) -> None:
        """Start polling the order book for all pairs.

        Creates a background task for each pair that polls independently.
        Blocks until stop() is called (like WS providers).
        """
        self._callback = callback
        self._running = True

        # Create a task per pair for independent polling
        self._tasks = [
            asyncio.create_task(self._poll_pair(pair))
            for pair in self._pairs
        ]

        logger.info(
            "[RestOB:%s] Started polling %d pair(s), interval=%.1fs",
            self.name, len(self._pairs), self._poll_interval,
        )

        # Wait for all tasks to complete (they run until cancelled)
        try:
            await asyncio.gather(*self._tasks)
        except asyncio.CancelledError:
            logger.info("[RestOB:%s] Polling cancelled", self.name)

    async def _poll_pair(self, pair: str) -> None:
        """Poll order book for a single pair in a loop."""
        while self._running:
            try:
                raw = await self._exchange.get_orderbook(pair, limit=20)
                if raw and raw.get("bids") and raw.get("asks"):
                    snap = OrderBookSnapshot(
                        pair=pair,
                        timestamp=datetime.now(timezone.utc),
                        bids=[(float(p), float(q)) for p, q in raw["bids"]],
                        asks=[(float(p), float(q)) for p, q in raw["asks"]],
                    )
                    if self._callback:
                        await self._callback(snap)
                else:
                    logger.debug(
                        "[RestOB:%s] Empty orderbook for %s",
                        self.name, pair,
                    )
            except Exception as e:
                logger.warning(
                    "[RestOB:%s] Poll error for %s: %s",
                    self.name, pair, e,
                )

            await asyncio.sleep(self._poll_interval)

    async def stop(self) -> None:
        """Stop all polling tasks."""
        self._running = False
        for task in self._tasks:
            if not task.done():
                task.cancel()
        if self._tasks:
            await asyncio.gather(*self._tasks, return_exceptions=True)
            self._tasks.clear()
        logger.info("[RestOB:%s] Stopped", self.name)
