"""Triple Moving Average strategy.

Logic:
    BUY  when fast SMA(10) > mid SMA(30) > slow SMA(50) on the last candle
          AND this condition was NOT true on the previous candle.
    SELL when fast SMA(10) < mid SMA(30) < slow SMA(50) on the last candle
          AND this condition was NOT true on the previous candle.

    Trend filter is directional:
      - BUY:  close > SMA(trend_filter_period)
      - SELL: close < SMA(trend_filter_period)

    Volume confirmation: current volume must exceed average of last 5 candles.

    Exit signal: alignment breaks (fast no longer > mid for BUY, or fast no longer < mid for SELL).

    Confidence is based on the minimum normalised gap between any two MAs.
    exit_target is calculated dynamically by the engine (entry ± ATR×2).
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
        fast_period: int = 10,
        mid_period: int = 30,
        slow_period: int = 50,
        min_gap_pct: float = 0.001,
    ) -> None:
        super().__init__(name="triple_ma")
        self.trend_filter_enabled = trend_filter_enabled
        self.trend_filter_period = trend_filter_period
        self.fast_period = fast_period
        self.mid_period = mid_period
        self.slow_period = slow_period
        self.min_gap_pct = min_gap_pct

    async def analyze(self, candles: List[Candle]) -> List[Signal]:
        """Analyze candles for triple MA alignment."""
        signals: List[Signal] = []
        min_candles = max(self.trend_filter_period, self.slow_period + 5) if self.trend_filter_enabled else self.slow_period + 5

        if len(candles) < min_candles:
            return signals

        sma_fast = SMA(period=self.fast_period)
        sma_mid = SMA(period=self.mid_period)
        sma_slow = SMA(period=self.slow_period)
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

        # BUY: newly bullish-aligned with minimum gap filters + uptrend
        if bullish_now and not bullish_before:
            fast_mid_gap = (fast_curr - mid_curr) / mid_curr if mid_curr != 0 else 0
            mid_slow_gap = (mid_curr - slow_curr) / slow_curr if slow_curr != 0 else 0
            if fast_mid_gap > self.min_gap_pct and mid_slow_gap > self.min_gap_pct:
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

        # SELL: newly bearish-aligned with minimum gap filters + downtrend
        elif bearish_now and not bearish_before:
            mid_fast_gap = (mid_curr - fast_curr) / fast_curr if fast_curr != 0 else 0
            slow_mid_gap = (slow_curr - mid_curr) / mid_curr if mid_curr != 0 else 0
            if mid_fast_gap > self.min_gap_pct and slow_mid_gap > self.min_gap_pct:
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

        # Exit signal: alignment broke (only if we had prior alignment)
        if bullish_before and not bullish_now:
            signals.append(
                Signal(
                    side="SELL",
                    price=current.close,
                    time=current.timestamp,
                    type="exit",
                    confidence=0.8,
                )
            )
        elif bearish_before and not bearish_now:
            signals.append(
                Signal(
                    side="BUY",
                    price=current.close,
                    time=current.timestamp,
                    type="exit",
                    confidence=0.8,
                )
            )

        return signals


# Backward compatibility alias
TripleMA = TripleMaStrategy
