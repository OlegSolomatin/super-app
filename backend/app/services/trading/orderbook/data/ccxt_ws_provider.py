"""WebSocket OrderBook data provider via ccxt.pro.

Uses ccxt.pro's watch_order_book() to stream real-time order book
data from any exchange that supports WebSocket order book streaming
(18+ exchanges: Gate, MEXC, KuCoin, OKX, Bitget, Kraken, etc.).

Architecture (ccxt Pro):
  - watch_order_book(symbol, limit) — subscribes to WS stream
  - Internal connection pool: one WS per exchange
  - On each update: full snapshot (ccxt pro handles diff+snapshot sync)
  - Reconnect: built-in ccxt exponential backoff

Trade-offs vs native WS providers:
  + Works with ANY exchange (18+ supported)
  + ~100-200ms latency (vs 1.5s REST polling)
  + Zero rate-limit usage (one WS connection)
  + Built-in reconnection
  - Slightly more overhead than native WS
  - Single exchange WS instance shared across all pairs

Usage:
    provider = CCXTWSProvider(
        pairs=["BTCUSDT", "ETHUSDT"],
        exchange_name="gate",
    )
    await provider.start(on_snapshot)
"""

from __future__ import annotations

import asyncio
import logging
from datetime import datetime, timezone
from typing import Any, Callable, Coroutine, Optional

import ccxt.pro as ccxt_pro

from app.services.trading.orderbook.data.base import DataProvider
from app.services.trading.orderbook.models import OrderBookSnapshot

logger = logging.getLogger(__name__)


class CCXTWSProvider(DataProvider):
    """WebSocket DataProvider using ccxt.pro watch_order_book().

    Supports any exchange where ccxt.pro has watchOrderBook=True.
    Uses one ccxt.pro Exchange instance per provider.
    Each pair gets an independent watch_order_book() task.
    """

    def __init__(
        self,
        pairs: list[str],
        exchange_name: str,
        market_type: str = "spot",
        orderbook_limit: int = 20,
    ) -> None:
        super().__init__(pairs)
        self._exchange_name = exchange_name.lower()
        self._market_type = market_type
        self._orderbook_limit = orderbook_limit
        self._exchange: Optional[ccxt_pro.Exchange] = None
        self._tasks: list[asyncio.Task] = []

    @property
    def name(self) -> str:
        return self._exchange_name

    def _convert_symbol(self, pair: str) -> str:
        """Convert internal pair to exchange format via ccxt markets."""
        if self._exchange and self._exchange.markets:
            # Try direct match
            if pair in self._exchange.markets:
                return pair
            # Try slash format: BTCUSDT → BTC/USDT
            if "/" not in pair and len(pair) > 5:
                for sep in ("/", "-"):
                    for be in range(len(pair) - 4, len(pair) - 2):
                        base = pair[:be]
                        quote = pair[be:]
                        fmt = f"{base}{sep}{quote}"
                        if fmt in self._exchange.markets:
                            return fmt
                        # Try swap format: BTC/USDT:USDT
                        if self._market_type in ("swap", "future"):
                            swap_fmt = f"{base}{sep}{quote}:{quote}"
                            if swap_fmt in self._exchange.markets:
                                return swap_fmt
        return pair

    async def _get_exchange(self) -> ccxt_pro.Exchange:
        """Get or create the ccxt.pro exchange instance."""
        if self._exchange is not None:
            return self._exchange

        exchange_class = getattr(ccxt_pro, self._exchange_name, None)
        if exchange_class is None:
            raise ValueError(
                f"Unsupported exchange: {self._exchange_name}. "
                f"Available: {', '.join(ccxt_pro.exchanges[:20])}..."
            )

        config = {
            "enableRateLimit": True,
            "options": {"defaultType": self._market_type},
        }
        self._exchange = exchange_class(config)

        # Load markets for proper symbol conversion
        try:
            await self._exchange.load_markets()
        except Exception as e:
            logger.warning(
                "[CCXTWS:%s] load_markets failed (non-fatal): %s",
                self._exchange_name, e,
            )

        logger.info(
            "[CCXTWS:%s] Exchange ready (watchOB=%s)",
            self._exchange_name,
            self._exchange.has.get("watchOrderBook", False),
        )
        return self._exchange

    async def start(
        self,
        callback: Callable[[OrderBookSnapshot],
                           Coroutine[Any, Any, None]],
    ) -> None:
        """Start WebSocket streaming for all pairs.

        Creates one watch_order_book() task per pair.
        Each task runs independently and reconnects on error.
        """
        self._callback = callback
        self._running = True

        ex = await self._get_exchange()

        self._tasks = [
            asyncio.create_task(self._watch_pair(ex, pair))
            for pair in self._pairs
        ]

        logger.info(
            "[CCXTWS:%s] Started %d pair(s) via WebSocket",
            self._exchange_name, len(self._pairs),
        )

        try:
            await asyncio.gather(*self._tasks)
        except asyncio.CancelledError:
            logger.info("[CCXTWS:%s] Tasks cancelled", self._exchange_name)

    async def _watch_pair(
        self,
        exchange: ccxt_pro.Exchange,
        pair: str,
    ) -> None:
        """Watch a single pair's order book via WebSocket in a loop.

        Uses ccxt.pro's built-in reconnection (exponential backoff).
        Each pair gets its own WS connection managed by ccxt.
        """
        symbol = self._convert_symbol(pair)
        reconnect_delay = 1.0

        while self._running:
            try:
                ob = await exchange.watch_order_book(
                    symbol,
                    limit=self._orderbook_limit,
                )

                if not self._running:
                    break

                bids_raw = ob.get("bids", [])
                asks_raw = ob.get("asks", [])

                if not bids_raw or not asks_raw:
                    continue

                bids = [(float(p), float(q)) for p, q in bids_raw if float(q) > 0]
                asks = [(float(p), float(q)) for p, q in asks_raw if float(q) > 0]

                if not bids or not asks:
                    continue

                snap = OrderBookSnapshot(
                    pair=pair,
                    timestamp=datetime.now(timezone.utc),
                    bids=bids,
                    asks=asks,
                )

                if self._callback:
                    await self._callback(snap)

                # Reset reconnect delay on successful snapshot
                reconnect_delay = 1.0

            except asyncio.CancelledError:
                break
            except Exception as e:
                if not self._running:
                    break
                logger.warning(
                    "[CCXTWS:%s] watch_order_book error for %s: %s. "
                    "Reconnect in %.1fs...",
                    self._exchange_name, pair, e, reconnect_delay,
                )
                await asyncio.sleep(reconnect_delay)
                reconnect_delay = min(reconnect_delay * 2, 30.0)

    async def stop(self) -> None:
        """Stop all WebSocket streaming tasks."""
        self._running = False

        for task in self._tasks:
            if not task.done():
                task.cancel()

        if self._tasks:
            await asyncio.gather(*self._tasks, return_exceptions=True)
            self._tasks.clear()

        # Close ccxt exchange (closes WS connections)
        if self._exchange:
            try:
                await self._exchange.close()
            except Exception:
                pass
            self._exchange = None

        logger.info("[CCXTWS:%s] Stopped", self._exchange_name)
