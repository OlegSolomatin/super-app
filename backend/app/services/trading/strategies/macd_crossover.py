"""MACD Crossover strategy (histogram-based).

Logic:
    Uses MACD(21, 50, 10) with histogram confirmation.

    BUY:
      - Histogram > 0 (positive)
      - Histogram rising for 2+ consecutive candles
      - MACD line > 0 (above zero)
      - Close > SMA(50) — short-term uptrend
      - Close > SMA(trend_filter_period) — long-term uptrend (BUY only)

    SELL:
      - Histogram < 0 (negative)
      - Histogram falling for 2+ consecutive candles
      - MACD line < 0 (below zero)
      - Close < SMA(50) — short-term downtrend
      - Close < SMA(trend_filter_period) — long-term downtrend (SELL only)

    Volume confirmation: current volume must exceed average of last 5 candles.

    Exit signal: histogram changes sign from positive to negative (or vice versa).

    Confidence is proportional to histogram magnitude normalised by price.
    exit_target is calculated dynamically by the engine (entry ± ATR×2).
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
        fast_period: int = 21,
        slow_period: int = 50,
        signal_period: int = 10,
    ) -> None:
        super().__init__(name="macd_crossover")
        self.trend_filter_enabled = trend_filter_enabled
        self.trend_filter_period = trend_filter_period
        self.fast_period = fast_period
        self.slow_period = slow_period
        self.signal_period = signal_period

    async def analyze(self, candles: List[Candle]) -> List[Signal]:
        """Analyze candles for MACD histogram confirmation signals."""
        signals: List[Signal] = []
        min_candles = max(self.trend_filter_period, self.slow_period + 10) if self.trend_filter_enabled else self.slow_period + 10

        if len(candles) < min_candles:
            return signals

        macd_indicator = MACD(fast_period=self.fast_period, slow_period=self.slow_period, signal_period=self.signal_period)
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

        # Compute SMA(50) for short-term trend
        sma50 = SMA(period=50)
        sma50_vals = sma50.compute(candles)
        if len(sma50_vals) < 1:
            return signals
        sma50_curr = sma50_vals[-1]
        if sma50_curr != sma50_curr:  # NaN check
            return signals

        # Long-term trend filter SMA
        tf_val: Optional[float] = None
        if self.trend_filter_enabled:
            sma_tf = SMA(period=self.trend_filter_period)
            tf_vals = sma_tf.compute(candles)
            tf_val = tf_vals[-1]
            if tf_val is not None and tf_val != tf_val:
                return signals

        # Volume confirmation
        if len(candles) >= 6:
            avg_vol = sum(c.volume for c in candles[-6:-1]) / 5.0
            volume_ok = current.volume > avg_vol
        else:
            volume_ok = True

        histogram = abs(hist_curr)
        confidence = min(1.0, histogram / current.close) if current.close != 0 else 0.0

        # BUY: histogram > 0 AND rising AND MACD line > 0 AND close > SMA(50)
        if (
            hist_curr > 0
            and hist_prev > 0
            and hist_curr > hist_prev
            and macd_curr > 0
            and current.close > sma50_curr
        ):
            # Long-term trend filter: only BUY in uptrend
            if tf_val is not None and current.close <= tf_val:
                return signals
            if not volume_ok:
                return signals
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
        elif (
            hist_curr < 0
            and hist_prev < 0
            and hist_curr < hist_prev
            and macd_curr < 0
            and current.close < sma50_curr
        ):
            # Long-term trend filter: only SELL in downtrend
            if tf_val is not None and current.close >= tf_val:
                return signals
            if not volume_ok:
                return signals
            signals.append(
                Signal(
                    side="SELL",
                    price=current.close,
                    time=current.timestamp,
                    type="entry",
                    confidence=confidence,
                )
            )

        # Exit signal: histogram changed sign
        if hist_curr > 0 and hist_prev <= 0:
            signals.append(
                Signal(
                    side="BUY",
                    price=current.close,
                    time=current.timestamp,
                    type="exit",
                    confidence=0.8,
                )
            )
        elif hist_curr < 0 and hist_prev >= 0:
            signals.append(
                Signal(
                    side="SELL",
                    price=current.close,
                    time=current.timestamp,
                    type="exit",
                    confidence=0.8,
                )
            )

        return signals


# Backward compatibility alias
MacdCrossover = MacdCrossoverStrategy
