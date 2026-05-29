"""Data loader — fetches OHLCV candles from exchanges or local storage.

Supports both historical (bulk) and live (streaming) data sources.
Currently uses MockExchange for synthetic data; future versions will
load from DB (trading_cached_klines) or via exchange API.
"""

from __future__ import annotations

from datetime import datetime, timedelta
from typing import AsyncGenerator, List, Optional

from app.services.trading.exchange.mock import MockExchange
from app.services.trading.models import Candle


class DataLoader:
    """Loads OHLCV candle data for a given pair and timeframe."""

    def __init__(self, pair: str, timeframe: str) -> None:
        self.pair = pair
        self.timeframe = timeframe

    async def load_history(
        self,
        start: datetime,
        end: datetime,
    ) -> List[Candle]:
        """Load historical candles between start and end timestamps.

        Uses MockExchange to generate synthetic data.
        In the future, will check DB cache first, then exchange API.
        """
        exchange = MockExchange()

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

        # Filter by time range and sort chronologically
        # Make timestamps timezone-naive for comparison
        _start = start.replace(tzinfo=None) if start.tzinfo else start
        _end = end.replace(tzinfo=None) if end.tzinfo else end
        candles = [c for c in candles if _start <= c.timestamp <= _end]
        candles.sort(key=lambda c: c.timestamp)
        return candles

    async def stream_live(self) -> AsyncGenerator[Candle, None]:
        """Yield live candles as they become available.

        Currently generates one mock candle per minute.
        """
        import asyncio

        exchange = MockExchange()
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
