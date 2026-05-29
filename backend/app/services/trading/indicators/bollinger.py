"""Bollinger Bands indicator.

Components:
    Middle Band = SMA(period)
    Upper Band  = Middle Band + (k * standard_deviation)
    Lower Band  = Middle Band - (k * standard_deviation)

Standard parameters: period=20, k=2 (number of standard deviations).
"""

from __future__ import annotations

from math import sqrt
from typing import List, Tuple

from app.services.trading.indicators.base import AbstractIndicator
from app.services.trading.indicators.sma import SMA
from app.services.trading.models import Candle


class BollingerBands(AbstractIndicator):
    """Bollinger Bands indicator.

    Returns triples of (upper_band, middle_band, lower_band).
    """

    def __init__(self, period: int = 20, k: float = 2.0) -> None:
        super().__init__(period=period)
        self.k = k

    def compute(self, candles: List[Candle]) -> List[Tuple[float, float, float]]:
        """Compute Bollinger Bands.

        Returns (upper, middle, lower) for each candle.
        Leading values are NaN until the period is warmed up.
        """
        sma_indicator = SMA(period=self.period)
        sma_values = sma_indicator.compute(candles)

        result: List[Tuple[float, float, float]] = []

        for i in range(len(candles)):
            if i < self.period - 1:
                result.append((float("nan"), float("nan"), float("nan")))
            else:
                middle = sma_values[i]
                # Standard deviation over the window
                window = candles[i - self.period + 1 : i + 1]
                mean = middle
                variance = sum((c.close - mean) ** 2 for c in window) / self.period
                std_dev = sqrt(variance)
                upper = middle + self.k * std_dev
                lower = middle - self.k * std_dev
                result.append((upper, middle, lower))

        return result
