"""Abstract base class for all technical indicators."""

from __future__ import annotations

from abc import ABC, abstractmethod
from typing import List

from app.services.trading.models import Candle


class AbstractIndicator(ABC):
    """Base class for technical indicators.

    Subclasses must implement compute() which accepts a list of candles
    and returns indicator values as floats.
    """

    def __init__(self, period: int = 14) -> None:
        self.period = period

    @abstractmethod
    def compute(self, candles: List[Candle]) -> List[float]:
        """Compute indicator values for the given candle list.

        Args:
            candles: OHLCV candles sorted chronologically (oldest first).

        Returns:
            A list of indicator values with the same length as candles.
            Leading values may be NaN until the indicator is warmed up.
        """
        ...
