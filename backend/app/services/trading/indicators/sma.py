"""Simple Moving Average (SMA) indicator.

Formula:
    SMA(i) = (1 / period) * sum(close[i-period+1 .. i])

SMA smooths price data by averaging closing prices over a sliding window.
"""

from __future__ import annotations

from typing import List

from app.services.trading.indicators.base import AbstractIndicator
from app.services.trading.models import Candle


class SMA(AbstractIndicator):
    """Simple Moving Average."""

    def compute(self, candles: List[Candle]) -> List[float]:
        """Compute SMA values.

        Returns NaN for the first (period - 1) positions.
        """
        result: List[float] = []
        cumulative = 0.0
        for i, c in enumerate(candles, start=1):
            cumulative += c.close
            if i < self.period:
                result.append(float("nan"))
            else:
                if i > self.period:
                    cumulative -= candles[i - self.period - 1].close
                result.append(cumulative / self.period)
        return result
