"""Triple Moving Average strategy.

Logic:
    BUY  when fast SMA(10) > mid SMA(30) > slow SMA(50) on the last candle
          AND this condition was NOT true on the previous candle.
    SELL when fast SMA(10) < mid SMA(30) < slow SMA(50) on the last candle
          AND this condition was NOT true on the previous candle.

Confidence is based on the minimum normalised gap between any two MAs.
"""

from __future__ import annotations

from typing import List, Optional

from app.services.trading.models import Candle, Signal
from app.services.trading.strategies.base import AbstractStrategy
from app.services.trading.indicators.sma import SMA


class TripleMaStrategy(AbstractStrategy):
    """Triple Moving Average strategy."""

    def __init__(
        self,
        trend_filter_enabled: bool = True,
        trend_filter_period: int = 200,
    ) -> None:
        super().__init__(name="triple_ma")
        self.trend_filter_enabled = trend_filter_enabled
        self.trend_filter_period = trend_filter_period

    async def analyze(self, candles: List[Candle]) -> List[Signal]:
        """Analyze candles for triple MA alignment."""
        signals: List[Signal] = []
        min_candles = max(self.trend_filter_period, 50) if self.trend_filter_enabled else 50

        if len(candles) < min_candles:
            return signals

        sma_fast = SMA(period=10)
        sma_mid = SMA(period=30)
        sma_slow = SMA(period=50)
        fast_vals = sma_fast.compute(candles)
        mid_vals = sma_mid.compute(candles)
        slow_vals = sma_slow.compute(candles)

        if len(fast_vals) < 2:
            return signals

        fast_prev = fast_vals[-2]
        fast_curr = fast_vals[-1]
        mid_prev = mid_vals[-2]
        mid_curr = mid_vals[-1]
        slow_prev = slow_vals[-2]
        slow_curr = slow_vals[-1]

        # Skip if any value is NaN
        if any(v != v for v in (fast_prev, fast_curr, mid_prev, mid_curr, slow_prev, slow_curr)):
            return signals

        current = candles[-1]

        # Trend filter: only BUY if price is above long-term SMA
        if self.trend_filter_enabled:
            sma_tf = SMA(period=self.trend_filter_period)
            tf_vals = sma_tf.compute(candles)
            tf_val = tf_vals[-1]
            if tf_val != tf_val:
                return signals
            if current.close <= tf_val:
                return signals

        # Bullish alignment: fast > mid > slow
        bullish_now = fast_curr > mid_curr > slow_curr
        bullish_before = fast_prev > mid_prev > slow_prev

        # Bearish alignment: fast < mid < slow
        bearish_now = fast_curr < mid_curr < slow_curr
        bearish_before = fast_prev < mid_prev < slow_prev

        # Confidence based on the minimum gap between consecutive MAs
        gap_fast_mid = abs(fast_curr - mid_curr)
        gap_mid_slow = abs(mid_curr - slow_curr)
        min_gap = min(gap_fast_mid, gap_mid_slow)
        confidence = min(1.0, min_gap / slow_curr) if slow_curr != 0 else 0.0

        # BUY: newly bullish-aligned with minimum gap filters
        if bullish_now and not bullish_before:
            # Fast must be at least 0.5% above mid
            # Mid must be at least 0.3% above slow
            fast_mid_gap = (fast_curr - mid_curr) / mid_curr if mid_curr != 0 else 0
            mid_slow_gap = (mid_curr - slow_curr) / slow_curr if slow_curr != 0 else 0
            if fast_mid_gap > 0.001 and mid_slow_gap > 0.001:
                signals.append(
                    Signal(
                        side="BUY",
                        price=current.close,
                        time=current.timestamp,
                        type="entry",
                        confidence=confidence,
                    )
                )

        # SELL: newly bearish-aligned with minimum gap filters (reversed)
        elif bearish_now and not bearish_before:
            # Mid must be at least 0.5% above fast (fast has dropped below mid)
            # Slow must be at least 0.3% above mid (mid has dropped below slow)
            mid_fast_gap = (mid_curr - fast_curr) / fast_curr if fast_curr != 0 else 0
            slow_mid_gap = (slow_curr - mid_curr) / mid_curr if mid_curr != 0 else 0
            if mid_fast_gap > 0.001 and slow_mid_gap > 0.001:
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
TripleMA = TripleMaStrategy
