"""Relative Strength Index (RSI) indicator.

Formula:
    RSI(i) = 100 - (100 / (1 + RS(i)))
    RS(i)  = avg_gain(i) / avg_loss(i)
    avg_gain(i) = (prev_avg_gain * (period-1) + current_gain) / period
    avg_loss(i) = (prev_avg_loss * (period-1) + current_loss) / period

RSI ranges from 0 to 100.  Values above 70 suggest overbought,
values below 30 suggest oversold.
"""

from __future__ import annotations

from typing import List

from app.services.trading.indicators.base import AbstractIndicator
from app.services.trading.models import Candle


class RSI(AbstractIndicator):
    """Relative Strength Index."""

    def compute(self, candles: List[Candle]) -> List[float]:
        """Compute RSI values.

        Returns NaN for the first period elements (no price change yet).
        Uses Wilder's smoothing method (EMA-like).
        """
        result: List[float] = []
        avg_gain = 0.0
        avg_loss = 0.0

        for i in range(1, len(candles) + 1):
            if i < self.period + 1:
                result.append(float("nan"))
                if i > 1:
                    change = candles[i - 1].close - candles[i - 2].close
                    if change > 0:
                        avg_gain += change
                    else:
                        avg_loss += abs(change)
                    if i == self.period:
                        avg_gain /= self.period
                        avg_loss /= self.period
            else:
                change = candles[i - 1].close - candles[i - 2].close
                gain = change if change > 0 else 0.0
                loss = abs(change) if change < 0 else 0.0
                avg_gain = (avg_gain * (self.period - 1) + gain) / self.period
                avg_loss = (avg_loss * (self.period - 1) + loss) / self.period
                rs = avg_gain / avg_loss if avg_loss != 0 else 100.0
                rsi_val = 100.0 - (100.0 / (1.0 + rs))
                result.append(rsi_val)

        return result
