"""Stochastic Oscillator strategy.

Logic:
    %K = (close - lowest_low(period)) / (highest_high(period) - lowest_low(period)) * 100
    %D = 3-period SMA of %K

    BUY:  %K was below 10 on previous candle, now > 10 AND > %D (exiting oversold zone)
    SELL: %K was above 90 on previous candle, now < 90 AND < %D (exiting overbought zone)

    Period = 14, smoothing = 3.
    Confidence is based on how extreme the %K value is:
      - BUY:  1.0 - %K / 100
      - SELL: %K / 100
"""

from __future__ import annotations

from typing import List, Optional

from app.services.trading.models import Candle, Signal
from app.services.trading.strategies.base import AbstractStrategy


class StochasticStrategy(AbstractStrategy):
    """Stochastic Oscillator strategy."""

    def __init__(
        self,
        trend_filter_enabled: bool = True,
        trend_filter_period: int = 200,
    ) -> None:
        super().__init__(name="stochastic")
        self.trend_filter_enabled = trend_filter_enabled
        self.trend_filter_period = trend_filter_period

    async def analyze(self, candles: List[Candle]) -> List[Signal]:
        """Analyze candles for stochastic crossover signals."""
        signals: List[Signal] = []
        min_candles = max(self.trend_filter_period, 20) if self.trend_filter_enabled else 20

        if len(candles) < min_candles:
            return signals

        period = 14
        smooth = 3

        if len(candles) < period + smooth:
            return signals

        # Compute %K values
        k_values: List[float] = []
        for i in range(len(candles)):
            if i < period - 1:
                k_values.append(float("nan"))
            else:
                window = candles[i - period + 1 : i + 1]
                highest_high = max(c.close for c in window)
                lowest_low = min(c.close for c in window)
                denominator = highest_high - lowest_low
                if denominator == 0:
                    k_values.append(50.0)  # neutral when range is zero
                else:
                    k_val = (candles[i].close - lowest_low) / denominator * 100.0
                    k_values.append(k_val)

        # Compute %D (3-period SMA of %K)
        d_values: List[float] = []
        for i in range(len(k_values)):
            if i < period - 1 + smooth - 1:
                d_values.append(float("nan"))
            else:
                d_val = sum(k_values[i - smooth + 1 : i + 1]) / smooth
                d_values.append(d_val)

        if len(k_values) < 2 or len(d_values) < 2:
            return signals

        k_prev = k_values[-2]
        k_curr = k_values[-1]
        d_prev = d_values[-2]
        d_curr = d_values[-1]

        # Skip if any value is NaN
        if any(v != v for v in (k_prev, k_curr, d_prev, d_curr)):
            return signals

        current = candles[-1]

        # Trend filter: only BUY if price is above long-term SMA
        if self.trend_filter_enabled:
            from app.services.trading.indicators.sma import SMA

            sma_tf = SMA(period=self.trend_filter_period)
            tf_vals = sma_tf.compute(candles)
            tf_val = tf_vals[-1]
            if tf_val != tf_val:
                return signals
            if current.close <= tf_val:
                return signals

        # BUY: %K < 15 AND %K crosses above %D (exiting oversold)
        if k_curr < 15 and k_prev <= d_prev and k_curr > d_curr:
            confidence = 1.0 - k_curr / 100.0
            signals.append(
                Signal(
                    side="BUY",
                    price=current.close,
                    time=current.timestamp,
                    type="entry",
                    confidence=confidence,
                )
            )

        # SELL: %K > 85 AND %K crosses below %D (exiting overbought)
        elif k_curr > 85 and k_prev >= d_prev and k_curr < d_curr:
            confidence = k_curr / 100.0
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
Stochastic = StochasticStrategy
