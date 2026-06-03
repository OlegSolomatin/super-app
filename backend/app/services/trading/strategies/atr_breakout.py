"""ATR Breakout strategy.

Logic:
    BUY  when current close > previous close + ATR(period) * multiplier
         (strong upward breakout) with volume confirmation.
    SELL when current close < previous close - ATR(period) * multiplier
         (strong downward breakout) with volume confirmation.

    Two-candle confirmation: the breakout candle must also close above
    the previous high (BUY) or below the previous low (SELL).

    Trend filter is directional:
      - BUY:  close > SMA(trend_filter_period)
      - SELL: close < SMA(trend_filter_period)

    Volume confirmation: current volume must exceed the previous candle's volume.

    ATR is computed using SMA of True Range over `atr_period` periods.

    Confidence is proportional to how many ATR multiples the move is.
    exit_target is calculated dynamically by the engine (entry ± ATR×2).
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
        atr_period: int = 14,
        multiplier: float = 2.0,
    ) -> None:
        super().__init__(name="atr_breakout")
        self.trend_filter_enabled = trend_filter_enabled
        self.trend_filter_period = trend_filter_period
        self.atr_period = atr_period
        self.multiplier = multiplier

    async def analyze(self, candles: List[Candle]) -> List[Signal]:
        """Analyze candles for ATR breakout signals."""
        signals: List[Signal] = []
        min_candles = self.atr_period + 2

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

        # ATR = SMA of True Range over atr_period
        sma_tr = SMA(period=self.atr_period)
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

        # Trend filter SMA
        tf_val: Optional[float] = None
        if self.trend_filter_enabled:
            sma_tf = SMA(period=self.trend_filter_period)
            tf_vals = sma_tf.compute(candles)
            tf_val = tf_vals[-1]
            if tf_val is not None and tf_val != tf_val:
                return signals

        # BUY: strong upward breakout with volume and 2-candle confirmation
        if current.close > previous.close + current_atr * self.multiplier:
            # Volume confirmation: current > previous
            if current.volume <= previous.volume:
                return signals
            # 2-candle confirmation: close above previous high
            if current.close <= previous.high:
                return signals
            # Directional trend filter: only BUY if close > SMA
            if tf_val is not None and current.close <= tf_val:
                return signals
            # Confidence proportional to ATR multiple
            atr_multiple = (current.close - previous.close) / current_atr if current_atr > 0 else self.multiplier
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

        # SELL: strong downward breakout with volume and 2-candle confirmation
        elif current.close < previous.close - current_atr * self.multiplier:
            if current.volume <= previous.volume:
                return signals
            # 2-candle confirmation: close below previous low
            if current.close >= previous.low:
                return signals
            # Directional trend filter: only SELL if close < SMA
            if tf_val is not None and current.close >= tf_val:
                return signals
            atr_multiple = (previous.close - current.close) / current_atr if current_atr > 0 else self.multiplier
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
