"""Moving Average Convergence Divergence (MACD) indicator.

Components:
    MACD line  = EMA(12) - EMA(26)
    Signal     = EMA(9) of MACD line
    Histogram  = MACD line - Signal line

Standard parameters: fast=12, slow=26, signal=9.
"""

from __future__ import annotations

from typing import List, Tuple

from app.services.trading.indicators.base import AbstractIndicator
from app.services.trading.indicators.ema import EMA
from app.services.trading.models import Candle


class MACD(AbstractIndicator):
    """Moving Average Convergence Divergence.

    Returns triples of (macd_line, signal_line, histogram).
    """

    def __init__(self, fast_period: int = 12, slow_period: int = 26, signal_period: int = 9) -> None:
        super().__init__(period=slow_period)
        self.fast_period = fast_period
        self.slow_period = slow_period
        self.signal_period = signal_period

    def compute(self, candles: List[Candle]) -> List[Tuple[float, float, float]]:
        """Compute MACD values.

        Returns (macd_line, signal_line, histogram) for each candle.
        Leading values are NaN until all periods are satisfied.
        """
        # Compute fast and slow EMAs
        fast_ema_indicator = EMA(period=self.fast_period)
        slow_ema_indicator = EMA(period=self.slow_period)
        fast_ema = fast_ema_indicator.compute(candles)
        slow_ema = slow_ema_indicator.compute(candles)

        # MACD line
        macd_line: List[float] = []
        for f, s in zip(fast_ema, slow_ema):
            macd_line.append(f - s if not (f != f or s != s) else float("nan"))

        # Signal line (EMA of MACD line)
        signal_indicator = EMA(period=self.signal_period)
        # Convert candles to a fake list for EMA computation on macd values
        from copy import deepcopy

        fake_candles = deepcopy(candles)
        for i, ml in enumerate(macd_line):
            fake_candles[i].close = ml if ml == ml else 0.0
        signal_line = signal_indicator.compute(fake_candles)

        # Histogram
        result: List[Tuple[float, float, float]] = []
        for ml, sl in zip(macd_line, signal_line):
            if ml != ml or sl != sl:
                result.append((float("nan"), float("nan"), float("nan")))
            else:
                result.append((ml, sl, ml - sl))

        return result
