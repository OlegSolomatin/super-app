"""Moving Average Crossover strategy.

Logic:
    BUY when short SMA (20) crosses above long SMA (50).
    SELL when short SMA crosses below long SMA.

    Crossover detection:
      - BUY:  SMA20[-1] > SMA50[-1]  AND  SMA20[-2] <= SMA50[-2]
      - SELL: SMA20[-1] < SMA50[-1]  AND  SMA20[-2] >= SMA50[-2]

    Confidence is proportional to the distance between the two MAs,
    normalised by the long MA value (to stay in the [0, 1] range).
"""

from __future__ import annotations

from typing import List, Optional

from app.services.trading.models import Candle, Signal
from app.services.trading.strategies.base import AbstractStrategy
from app.services.trading.indicators.sma import SMA


class MaCrossoverStrategy(AbstractStrategy):
    """Moving Average Crossover strategy."""

    def __init__(
        self,
        trend_filter_enabled: bool = True,
        trend_filter_period: int = 200,
    ) -> None:
        super().__init__(name="ma_crossover")
        self.trend_filter_enabled = trend_filter_enabled
        self.trend_filter_period = trend_filter_period

    async def analyze(self, candles: List[Candle]) -> List[Signal]:
        """Analyze candles for MA crossovers.

        Returns a BUY or SELL signal when the short and long SMAs cross.
        """
        signals: List[Signal] = []
        min_candles = max(self.trend_filter_period, 50) if self.trend_filter_enabled else 50

        if len(candles) < min_candles:
            return signals

        sma_short = SMA(period=20)
        sma_long = SMA(period=50)
        short_vals = sma_short.compute(candles)
        long_vals = sma_long.compute(candles)

        # We need at least three valid SMA values to detect a fresh crossover
        if len(short_vals) < 3 or len(long_vals) < 3:
            return signals

        short_prev2 = short_vals[-3]
        short_prev = short_vals[-2]
        short_curr = short_vals[-1]
        long_prev2 = long_vals[-3]
        long_prev = long_vals[-2]
        long_curr = long_vals[-1]

        # Skip if any value is NaN
        if any(v != v for v in (short_prev2, short_prev, short_curr, long_prev2, long_prev, long_curr)):
            return signals

        current = candles[-1]

        # Trend filter: only BUY if price is above long-term SMA
        if self.trend_filter_enabled:
            sma_tf = SMA(period=self.trend_filter_period)
            tf_vals = sma_tf.compute(candles)
            tf_val = tf_vals[-1]
            if tf_val != tf_val:  # NaN check
                return signals
            if current.close <= tf_val:
                return signals

        distance = abs(short_curr - long_curr)
        min_gap_ok = distance / long_curr > 0.001 if long_curr != 0 else False
        confidence = min(1.0, distance / long_curr) if long_curr != 0 else 0.0

        # BUY signal: fresh crossover above with minimum gap
        # short was below long 2 candles ago (fresh crossover), and minimum 0.3% gap
        if short_curr > long_curr and short_prev <= long_prev and min_gap_ok:
            signals.append(
                Signal(
                    side="BUY",
                    price=current.close,
                    time=current.timestamp,
                    type="entry",
                    confidence=confidence,
                )
            )

        # SELL signal: fresh crossover below with minimum gap
        elif short_curr < long_curr and short_prev >= long_prev and min_gap_ok:
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
MaCrossover = MaCrossoverStrategy
