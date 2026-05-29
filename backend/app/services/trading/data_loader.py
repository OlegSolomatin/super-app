"""Data loader — fetches OHLCV candles from exchanges or local storage.

Supports both historical (bulk) and live (streaming) data sources.
Currently uses MockExchange for synthetic data; future versions will
load from DB (trading_cached_klines) or via exchange API.
"""

from __future__ import annotations

import logging
from datetime import datetime, timedelta, timezone
from typing import AsyncGenerator, List, Optional

logger = logging.getLogger(__name__)

from app.services.trading.exchange.binance import BinanceExchange
from app.services.trading.exchange.bybit import BybitExchange
from app.services.trading.exchange.mock import MockExchange
from app.services.trading.models import Candle


class DataLoader:
    """Loads OHLCV candle data for a given pair and timeframe from a specified exchange."""

    def __init__(self, pair: str, timeframe: str, exchange_name: str = "binance") -> None:
        self.pair = pair
        self.timeframe = timeframe
        self.exchange_name = exchange_name

    def _create_exchange(self):
        """Create exchange connector by name."""
        name = self.exchange_name.lower()
        if name == "binance":
            return BinanceExchange()
        elif name == "bybit":
            return BybitExchange()
        elif name == "mock":
            return MockExchange()
        else:
            logger.warning("Unknown exchange '%s', falling back to mock", name)
            return MockExchange()

    async def load_history(
        self,
        start: datetime,
        end: datetime,
    ) -> List[Candle]:
        """Load historical candles between start and end timestamps.

        Uses the configured exchange (binance/bybit/mock).
        """
        exchange = self._create_exchange()

        # Calculate approximate number of candles needed
        tf_minutes = self._timeframe_minutes(self.timeframe)
        if tf_minutes <= 0:
            tf_minutes = 60  # default to 1h

        total_minutes = (end - start).total_seconds() / 60
        limit = max(10, min(5000, int(total_minutes / tf_minutes) + 1))

        candles = await exchange.get_klines(
            pair=self.pair,
            timeframe=self.timeframe,
            start=start,
            end=end,
            limit=limit,
        )

        # Filter by time range and sort
        _start = start.astimezone(timezone.utc) if start else start
        _end = end.astimezone(timezone.utc) if end else end
        candles = [c for c in candles if _start <= c.timestamp.replace(tzinfo=timezone.utc) <= _end]
        candles.sort(key=lambda c: c.timestamp)
        return candles

    async def stream_live(self) -> AsyncGenerator[Candle, None]:
        """Yield live candles as they become available.

        Currently generates one mock candle per minute.
        """
        import asyncio

        exchange = self._create_exchange()
        while True:
            candles = await exchange.get_klines(
                pair=self.pair,
                timeframe=self.timeframe,
                limit=1,
            )
            if candles:
                yield candles[0]
            await asyncio.sleep(60)  # Wait before next candle

    @staticmethod
    def _timeframe_minutes(timeframe: str) -> int:
        """Convert a timeframe string (e.g. '1h', '15m', '1d') to minutes."""
        if not isinstance(timeframe, str):
            return 60
        timeframe = timeframe.strip().lower()
        if timeframe.endswith("m"):
            return int(timeframe[:-1])
        elif timeframe.endswith("h"):
            return int(timeframe[:-1]) * 60
        elif timeframe.endswith("d"):
            return int(timeframe[:-1]) * 1440
        elif timeframe.endswith("w"):
            return int(timeframe[:-1]) * 10080
        else:
            return 60
