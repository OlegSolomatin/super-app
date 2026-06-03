"""Moving Average Crossover strategy.

Logic:
    BUY when short SMA crosses above long SMA.
    SELL when short SMA crosses below long SMA.

    Crossover detection:
      - BUY:  SMA_fast[-1] > SMA_slow[-1]  AND  SMA_fast[-2] <= SMA_slow[-2]
      - SELL: SMA_fast[-1] < SMA_slow[-1]  AND  SMA_fast[-2] >= SMA_slow[-2]

    Trend filter is directional:
      - BUY:  close > SMA(trend_filter_period) — only buy in uptrend
      - SELL: close < SMA(trend_filter_period) — only sell in downtrend

    Volume confirmation: current volume must exceed average of last 5 candles.

    Confidence is proportional to the distance between the two MAs,
    normalised by the long MA value (to stay in the [0, 1] range).
    exit_target is calculated dynamically by the engine (entry ± ATR×2).
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
        fast_period: int = 20,
        slow_period: int = 50,
        min_gap_pct: float = 0.001,
    ) -> None:
        super().__init__(name="ma_crossover")
        self.trend_filter_enabled = trend_filter_enabled
        self.trend_filter_period = trend_filter_period
        self.fast_period = fast_period
        self.slow_period = slow_period
        self.min_gap_pct = min_gap_pct

    async def analyze(self, candles: List[Candle]) -> List[Signal]:
        """Analyze candles for MA crossovers.

        Returns a BUY or SELL signal when the short and long SMAs cross,
        with directional trend filter and volume confirmation.
        """
        signals: List[Signal] = []
        min_candles = max(self.trend_filter_period, self.slow_period + 5) if self.trend_filter_enabled else self.slow_period + 5

        if len(candles) < min_candles:
            return signals

        sma_short = SMA(period=self.fast_period)
        sma_long = SMA(period=self.slow_period)
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

        # Trend filter SMA
        tf_val: Optional[float] = None
        if self.trend_filter_enabled:
            sma_tf = SMA(period=self.trend_filter_period)
            tf_vals = sma_tf.compute(candles)
            tf_val = tf_vals[-1]
            if tf_val is not None and tf_val != tf_val:  # NaN check
                return signals

        # Volume confirmation: current volume > avg volume of last 5 candles
        if len(candles) >= 6:
            avg_vol = sum(c.volume for c in candles[-6:-1]) / 5.0
            volume_ok = current.volume > avg_vol
        else:
            volume_ok = True

        distance = abs(short_curr - long_curr)
        min_gap_ok = distance / long_curr > self.min_gap_pct if long_curr != 0 else False
        confidence = min(1.0, distance / long_curr) if long_curr != 0 else 0.0

        # BUY signal: fresh crossover above with minimum gap AND uptrend
        if short_curr > long_curr and short_prev <= long_prev and min_gap_ok:
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

        # SELL signal: fresh crossover below with minimum gap AND downtrend
        elif short_curr < long_curr and short_prev >= long_prev and min_gap_ok:
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


# Backward compatibility alias
MaCrossover = MaCrossoverStrategy
