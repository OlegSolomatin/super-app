"""Parabolic SAR strategy.

Logic:
    Parabolic SAR is calculated manually:
      - Uptrend start:  SAR = lowest low of the initial downtrend
      - Downtrend start: SAR = highest high of the initial uptrend
      - Acceleration factor starts at 0.02, increases by 0.02 each time a
        new extreme (high in uptrend, low in downtrend) is made, capped at 0.20.

    BUY  when SAR < close (uptrend has started — SAR flips below price).
    SELL when SAR > close (downtrend has started — SAR flips above price).

    Confidence is based on the normalised distance between close and SAR.
"""

from __future__ import annotations

from typing import List, Optional

from app.services.trading.models import Candle, Signal
from app.services.trading.strategies.base import AbstractStrategy
from app.services.trading.indicators.sma import SMA


class ParabolicSarStrategy(AbstractStrategy):
    """Parabolic SAR strategy with manual SAR calculation."""

    def __init__(
        self,
        trend_filter_enabled: bool = True,
        trend_filter_period: int = 200,
        acceleration: float = 0.03,
        max_acceleration: float = 0.10,
    ) -> None:
        super().__init__(name="parabolic_sar")
        self.trend_filter_enabled = trend_filter_enabled
        self.trend_filter_period = trend_filter_period
        self.acceleration = acceleration
        self.max_acceleration = max_acceleration

    async def analyze(self, candles: List[Candle]) -> List[Signal]:
        """Analyze candles for Parabolic SAR signals."""
        signals: List[Signal] = []
        min_candles = max(self.trend_filter_period, 3) if self.trend_filter_enabled else 3

        if len(candles) < min_candles:
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

        # Compute SAR values for the full candle series
        sar_values = self._compute_sar(candles)

        if len(sar_values) < 2:
            return signals

        sar_prev = sar_values[-2]
        sar_curr = sar_values[-1]

        if sar_prev != sar_prev or sar_curr != sar_curr:  # NaN check
            return signals

        # Detect flips:
        # BUY: SAR was above price (downtrend) and is now below (uptrend flip)
        # We detect this by looking at the last two SAR vs close relationships
        prev_uptrend = sar_prev < candles[-2].close
        curr_uptrend = sar_curr < current.close

        distance = abs(current.close - sar_curr)
        confidence = min(1.0, distance / current.close) if current.close != 0 else 0.0

        # BUY: both previous and current candles in uptrend (2-candle confirmation)
        if curr_uptrend and prev_uptrend:
            # Directional trend filter: only BUY if close > SMA
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

        # SELL: both previous and current candles in downtrend (2-candle confirmation)
        elif not curr_uptrend and not prev_uptrend:
            # Directional trend filter: only SELL if close < SMA
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

        return signals

    def _compute_sar(self, candles: List[Candle]) -> List[float]:
        """Compute Parabolic SAR values for all candles.

        Returns a list of SAR values (same length as candles). Initial values
        before a trend is established are NaN.
        """
        n = len(candles)
        sar: List[float] = [float("nan")] * n

        if n < 2:
            return sar

        # Initialise with the first two candles
        # Determine initial trend
        is_uptrend = candles[1].close > candles[0].close

        if is_uptrend:
            ep = max(candles[0].high, candles[1].high)  # extreme point
            sar[0] = min(candles[0].low, candles[1].low)
        else:
            ep = min(candles[0].low, candles[1].low)
            sar[0] = max(candles[0].high, candles[1].high)

        af = self.acceleration

        for i in range(1, n):
            if is_uptrend:
                sar[i] = sar[i - 1] + af * (ep - sar[i - 1])
                # SAR cannot be above the current or previous candle low
                sar[i] = min(sar[i], candles[i - 1].low if i > 0 else sar[i])
                sar[i] = min(sar[i], candles[i].low)

                # Check for flip
                if sar[i] >= candles[i].close:
                    # Flip to downtrend
                    is_uptrend = False
                    sar[i] = ep  # set to previous extreme point
                    ep = candles[i].low
                    af = self.acceleration
                else:
                    # Update extreme point and acceleration factor
                    if candles[i].high > ep:
                        ep = candles[i].high
                        af = min(af + self.acceleration, self.max_acceleration)
            else:
                sar[i] = sar[i - 1] - af * (sar[i - 1] - ep)
                # SAR cannot be below the current or previous candle high
                sar[i] = max(sar[i], candles[i - 1].high if i > 0 else sar[i])
                sar[i] = max(sar[i], candles[i].high)

                # Check for flip
                if sar[i] <= candles[i].close:
                    # Flip to uptrend
                    is_uptrend = True
                    sar[i] = ep  # set to previous extreme point
                    ep = candles[i].high
                    af = self.acceleration
                else:
                    # Update extreme point and acceleration factor
                    if candles[i].low < ep:
                        ep = candles[i].low
                        af = min(af + self.acceleration, self.max_acceleration)

        return sar


# Backward compatibility alias
ParabolicSAR = ParabolicSarStrategy
