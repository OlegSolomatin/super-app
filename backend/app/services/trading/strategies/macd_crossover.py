"""MACD Crossover strategy (histogram-based).

Logic:
    Uses MACD(21, 50, 10) with histogram confirmation instead of crossover.
    
    BUY:
      - Histogram > 0 (positive)
      - Histogram rising for 2+ consecutive candles
      - MACD line > 0 (above zero)
      - Close > SMA(50) — simple trend filter
    
    SELL:
      - Histogram < 0 (negative)
      - Histogram falling for 2+ consecutive candles
      - MACD line < 0 (below zero)
      - Close < SMA(50)

    Confidence is proportional to histogram magnitude normalised by price.
"""

from __future__ import annotations

from typing import List, Optional

from app.services.trading.models import Candle, Signal
from app.services.trading.strategies.base import AbstractStrategy
from app.services.trading.indicators.macd import MACD
from app.services.trading.indicators.sma import SMA


class MacdCrossoverStrategy(AbstractStrategy):
    """MACD Crossover strategy (histogram-based)."""

    def __init__(
        self,
        trend_filter_enabled: bool = True,
        trend_filter_period: int = 200,
    ) -> None:
        super().__init__(name="macd_crossover")
        self.trend_filter_enabled = trend_filter_enabled
        self.trend_filter_period = trend_filter_period

    async def analyze(self, candles: List[Candle]) -> List[Signal]:
        """Analyze candles for MACD histogram confirmation signals."""
        signals: List[Signal] = []
        min_candles = max(self.trend_filter_period, 60) if self.trend_filter_enabled else 60

        if len(candles) < min_candles:
            return signals

        macd_indicator = MACD(fast_period=21, slow_period=50, signal_period=10)
        macd_values = macd_indicator.compute(candles)

        if len(macd_values) < 3:
            return signals

        # Last 3 histogram values: tuple is (macd_line, signal_line, histogram)
        hist_prev2 = macd_values[-3][2]
        hist_prev = macd_values[-2][2]
        hist_curr = macd_values[-1][2]
        macd_curr = macd_values[-1][0]

        # Skip if any value is NaN
        if any(v != v for v in (hist_prev2, hist_prev, hist_curr, macd_curr)):
            return signals

        current = candles[-1]

        # Compute SMA(50) for trend filter
        sma50 = SMA(period=50)
        sma50_vals = sma50.compute(candles)
        if len(sma50_vals) < 1:
            return signals
        sma50_curr = sma50_vals[-1]
        if sma50_curr != sma50_curr:  # NaN check
            return signals

        # Trend filter: only BUY if price is above long-term SMA
        if self.trend_filter_enabled:
            sma_tf = SMA(period=self.trend_filter_period)
            tf_vals = sma_tf.compute(candles)
            tf_val = tf_vals[-1]
            if tf_val != tf_val:
                return signals
            if current.close <= tf_val:
                return signals

        histogram = abs(hist_curr)
        confidence = min(1.0, histogram / current.close) if current.close != 0 else 0.0

        # BUY: histogram > 0 AND rising AND MACD line > 0 AND close > SMA(50)
        if hist_curr > 0 and hist_prev > 0 and hist_curr > hist_prev and macd_curr > 0 and current.close > sma50_curr:
            signals.append(
                Signal(
                    side="BUY",
                    price=current.close,
                    time=current.timestamp,
                    type="entry",
                    confidence=confidence,
                )
            )

        # SELL: histogram < 0 AND falling AND MACD line < 0 AND close < SMA(50)
        elif hist_curr < 0 and hist_prev < 0 and hist_curr < hist_prev and macd_curr < 0 and current.close < sma50_curr:
            signals.append(
                Signal(
                    side="SELL",
                    price=current.close,
                    time=current.timestamp,
                    type="entry",
                    confidence=confidence,
                )
            )

        return signals


# Backward compatibility alias
MacdCrossover = MacdCrossoverStrategy
