"""ATR Breakout strategy.

Logic:
    BUY  when current close > previous close + ATR(14) * 2.0  (strong upward breakout)
    SELL when current close < previous close - ATR(14) * 2.0  (strong downward breakout)

    Volume confirmation is required — current volume must be higher than
    the previous candle's volume.

    ATR is computed inline using:
      True Range = max(high - low, |high - prev_close|, |low - prev_close|)
      ATR = SMA of True Range over 14 periods.

    Confidence is proportional to how many ATR multiples the move is.
"""

from __future__ import annotations

from typing import List, Optional

from app.services.trading.models import Candle, Signal
from app.services.trading.strategies.base import AbstractStrategy
from app.services.trading.indicators.sma import SMA


class ATRBreakout(AbstractStrategy):
    """ATR-based breakout strategy with volume confirmation."""

    def __init__(
        self,
        trend_filter_enabled: bool = True,
        trend_filter_period: int = 200,
    ) -> None:
        super().__init__(name="atr_breakout")
        self.trend_filter_enabled = trend_filter_enabled
        self.trend_filter_period = trend_filter_period

    async def analyze(self, candles: List[Candle]) -> List[Signal]:
        """Analyze candles for ATR breakout signals."""
        signals: List[Signal] = []
        atr_period = 14
        multiplier = 2.0
        min_candles = atr_period + 1

        if len(candles) < min_candles:
            return signals

        # Compute True Range values
        tr_values: List[float] = []
        for i in range(len(candles)):
            if i == 0:
                tr_values.append(candles[i].high - candles[i].low)
            else:
                high_low = candles[i].high - candles[i].low
                high_close = abs(candles[i].high - candles[i - 1].close)
                low_close = abs(candles[i].low - candles[i - 1].close)
                tr_values.append(max(high_low, high_close, low_close))

        # ATR = SMA of True Range over 14 periods
        sma_tr = SMA(period=atr_period)
        atr_values = sma_tr.compute(
            [Candle(open=0, high=0, low=0, close=tr_values[i], volume=0, timestamp=candles[i].timestamp)
             for i in range(len(tr_values))]
        )

        current = candles[-1]
        previous = candles[-2]
        current_atr = atr_values[-1]

        # Skip if ATR is NaN
        if current_atr != current_atr:
            return signals

        # SMA(50) trend filter: BUY only in uptrend, SELL only in downtrend
        sma50 = SMA(period=50)
        sma50_vals = sma50.compute(candles)
        sma50_val = sma50_vals[-1]
        if sma50_val != sma50_val:
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

        # BUY: strong upward breakout with volume confirmation
        if current.close > previous.close + current_atr * multiplier and current.close > sma50_val:
            if current.volume > previous.volume:
                # Confidence proportional to ATR multiple
                atr_multiple = (current.close - previous.close) / current_atr if current_atr > 0 else multiplier
                confidence = min(1.0, atr_multiple / 3.0)
                signals.append(
                    Signal(
                        side="BUY",
                        price=current.close,
                        time=current.timestamp,
                        type="entry",
                        confidence=confidence,
                    )
                )

        # SELL: strong downward breakout with volume confirmation
        elif current.close < previous.close - current_atr * multiplier and current.close < sma50_val:
            if current.volume > previous.volume:
                atr_multiple = (previous.close - current.close) / current_atr if current_atr > 0 else multiplier
                confidence = min(1.0, atr_multiple / 3.0)
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
ATRBreakoutStrategy = ATRBreakout
