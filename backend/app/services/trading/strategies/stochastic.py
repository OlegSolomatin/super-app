"""Stochastic Oscillator strategy.

Logic:
    %K = (close - lowest_low(period)) / (highest_high(period) - lowest_low(period)) * 100
    %D = 3-period SMA of %K

    BUY:  %K was below oversold on previous candle, now > %D (exiting oversold zone)
    SELL: %K was above overbought on previous candle, now < %D (exiting overbought zone)

    Trend filter is directional:
      - BUY:  close > SMA(trend_filter_period)
      - SELL: close < SMA(trend_filter_period)

    Volume confirmation: current volume must exceed average of last 5 candles.

    Confidence is based on how extreme the %K value is.
    exit_target is calculated dynamically by the engine (entry ± ATR×2).
"""

from __future__ import annotations

from typing import List, Optional

from app.services.trading.models import Candle, Signal
from app.services.trading.strategies.base import AbstractStrategy
from app.services.trading.indicators.sma import SMA


class StochasticStrategy(AbstractStrategy):
    """Stochastic Oscillator strategy."""

    def __init__(
        self,
        trend_filter_enabled: bool = True,
        trend_filter_period: int = 200,
        k_period: int = 14,
        d_smoothing: int = 3,
        oversold: float = 15.0,
        overbought: float = 85.0,
    ) -> None:
        super().__init__(name="stochastic")
        self.trend_filter_enabled = trend_filter_enabled
        self.trend_filter_period = trend_filter_period
        self.k_period = k_period
        self.d_smoothing = d_smoothing
        self.oversold = oversold
        self.overbought = overbought

    async def analyze(self, candles: List[Candle]) -> List[Signal]:
        """Analyze candles for stochastic crossover signals."""
        signals: List[Signal] = []
        min_candles = max(self.trend_filter_period, self.k_period + self.d_smoothing + 5) if self.trend_filter_enabled else self.k_period + self.d_smoothing + 5

        if len(candles) < min_candles:
            return signals

        if len(candles) < self.k_period + self.d_smoothing:
            return signals

        # Compute %K values
        k_values: List[float] = []
        for i in range(len(candles)):
            if i < self.k_period - 1:
                k_values.append(float("nan"))
            else:
                window = candles[i - self.k_period + 1 : i + 1]
                highest_high = max(c.close for c in window)
                lowest_low = min(c.close for c in window)
                denominator = highest_high - lowest_low
                if denominator == 0:
                    k_values.append(50.0)  # neutral when range is zero
                else:
                    k_val = (candles[i].close - lowest_low) / denominator * 100.0
                    k_values.append(k_val)

        # Compute %D (SMA of %K)
        d_values: List[float] = []
        for i in range(len(k_values)):
            if i < self.k_period - 1 + self.d_smoothing - 1:
                d_values.append(float("nan"))
            else:
                d_val = sum(k_values[i - self.d_smoothing + 1 : i + 1]) / self.d_smoothing
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

        # Trend filter SMA
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

        # BUY: %K < oversold AND %K crosses above %D (exiting oversold)
        if k_curr < self.oversold and k_prev <= d_prev and k_curr > d_curr:
            # Directional trend filter: only BUY if close > SMA
            if tf_val is not None and current.close <= tf_val:
                return signals
            if not volume_ok:
                return signals
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

        # SELL: %K > overbought AND %K crosses below %D (exiting overbought)
        elif k_curr > self.overbought and k_prev >= d_prev and k_curr < d_curr:
            # Directional trend filter: only SELL if close < SMA
            if tf_val is not None and current.close >= tf_val:
                return signals
            if not volume_ok:
                return signals
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
