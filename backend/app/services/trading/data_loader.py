"""Data loader — fetches OHLCV candles from exchanges or local storage.

Supports both historical (bulk) and live (streaming) data sources.
"""

from __future__ import annotations

from datetime import datetime
from typing import AsyncGenerator, List, Optional

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
        """Load historical candles between start and end timestamps."""
        # TODO: implement data fetching from exchange API or DB
        return []

    async def stream_live(self) -> AsyncGenerator[Candle, None]:
        """Yield live candles as they become available."""
        # TODO: implement websocket streaming
        yield Candle(
            open=0.0,
            high=0.0,
            low=0.0,
            close=0.0,
            volume=0.0,
            timestamp=datetime.now(),
        )
