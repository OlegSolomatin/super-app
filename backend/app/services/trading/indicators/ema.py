"""Exponential Moving Average (EMA) indicator.

Formula:
    multiplier = 2 / (period + 1)
    EMA(1) = close(1)  (seed with first close)
    EMA(i) = (close(i) - EMA(i-1)) * multiplier + EMA(i-1)

EMA gives more weight to recent prices, reacting faster than SMA.
"""

from __future__ import annotations

from typing import List

from app.services.trading.indicators.base import AbstractIndicator
from app.services.trading.models import Candle


class EMA(AbstractIndicator):
    """Exponential Moving Average."""

    def compute(self, candles: List[Candle]) -> List[float]:
        """Compute EMA values.

        Returns NaN for the first (period - 1) positions.  Seed uses SMA
        of the first period values for better stability.
        """
        result: List[float] = []
        multiplier = 2.0 / (self.period + 1)
        ema_prev = 0.0
        seeded = False

        for i, c in enumerate(candles, start=1):
            if i < self.period:
                result.append(float("nan"))
                if i == 1:
                    ema_prev = c.close
                else:
                    ema_prev += c.close
            elif not seeded:
                # Seed EMA with SMA of first period values
                ema_prev = ema_prev / self.period
                result.append(ema_prev)
                seeded = True
            else:
                ema_prev = (c.close - ema_prev) * multiplier + ema_prev
                result.append(ema_prev)

        return result
