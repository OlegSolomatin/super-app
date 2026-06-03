"""Keltner Channels strategy.

Logic:
    Middle line = EMA(20)
    Upper band = EMA + ATR(14) * 2
    Lower band = EMA - ATR(14) * 2

    BUY  when close crosses above the Upper band (upside breakout).
    SELL when close crosses below the Lower band (downside breakdown).

    ATR is computed inline using:
      True Range = max(high - low, |high - prev_close|, |low - prev_close|)
      ATR = SMA of True Range over 14 periods.

    Confidence is proportional to how far price is beyond the band.
"""

from __future__ import annotations

from typing import List, Optional

from app.services.trading.models import Candle, Signal
from app.services.trading.strategies.base import AbstractStrategy
from app.services.trading.indicators.ema import EMA
from app.services.trading.indicators.sma import SMA
from app.services.trading.indicators.rsi import RSI


class KeltnerChannels(AbstractStrategy):
    """Keltner Channels breakout strategy."""

    def __init__(
        self,
        trend_filter_enabled: bool = True,
        trend_filter_period: int = 200,
        ema_period: int = 20,
        atr_period: int = 14,
        multiplier: float = 2.5,
    ) -> None:
        super().__init__(name="keltner_channels")
        self.trend_filter_enabled = trend_filter_enabled
        self.trend_filter_period = trend_filter_period
        self.ema_period = ema_period
        self.atr_period = atr_period
        self.multiplier = multiplier

    async def analyze(self, candles: List[Candle]) -> List[Signal]:
        """Analyze candles for Keltner Channel breakout signals."""
        signals: List[Signal] = []
        min_candles = (
            max(self.trend_filter_period, self.ema_period + self.atr_period)
            if self.trend_filter_enabled
            else self.ema_period + self.atr_period
        )

        if len(candles) < min_candles:
            return signals

        # Compute EMA
        ema_indicator = EMA(period=self.ema_period)
        ema_values = ema_indicator.compute(candles)

        # Compute ATR inline
        tr_values: List[float] = []
        for i in range(len(candles)):
            if i == 0:
                tr_values.append(candles[i].high - candles[i].low)
            else:
                high_low = candles[i].high - candles[i].low
                high_close = abs(candles[i].high - candles[i - 1].close)
                low_close = abs(candles[i].low - candles[i - 1].close)
                tr_values.append(max(high_low, high_close, low_close))

        # ATR = SMA of True Range
        sma_tr = SMA(period=self.atr_period)
        atr_values = sma_tr.compute(
            [Candle(open=0, high=0, low=0, close=tr_values[i], volume=0, timestamp=candles[i].timestamp)
             for i in range(len(tr_values))]
        )

        current = candles[-1]
        curr_ema = ema_values[-1]
        curr_atr = atr_values[-1]

        # Skip if any value is NaN
        if curr_ema != curr_ema or curr_atr != curr_atr:
            return signals

        # RSI filter for trend confirmation
        rsi_indicator = RSI(period=14)
        rsi_values = rsi_indicator.compute(candles)
        rsi_curr = rsi_values[-1]
        if rsi_curr != rsi_curr:
            return signals

        # EMA(50) directional filter
        ema50 = SMA(period=50)
        ema50_vals = ema50.compute(candles)
        ema50_val = ema50_vals[-1]
        if ema50_val != ema50_val:
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

        upper = curr_ema + curr_atr * self.multiplier
        lower = curr_ema - curr_atr * self.multiplier

        prev_ema = ema_values[-2] if len(ema_values) >= 2 else float("nan")
        prev_atr = atr_values[-2] if len(atr_values) >= 2 else float("nan")
        prev_upper = prev_ema + prev_atr * self.multiplier if prev_ema == prev_ema and prev_atr == prev_atr else float("nan")
        prev_lower = prev_ema - prev_atr * self.multiplier if prev_ema == prev_ema and prev_atr == prev_atr else float("nan")

        # BUY: close crosses above Upper band (only if RSI > 50 confirming uptrend)
        if current.close > upper and rsi_curr > 50 and current.close > ema50_val:
            # Directional trend filter: only BUY if close > SMA
            if tf_val is not None and current.close <= tf_val:
                return signals
            if not volume_ok:
                return signals
            if prev_upper != prev_upper or candles[-2].close <= prev_upper:
                # Cross above — price was below or at upper, now above
                band_width = upper - lower if upper > lower else 1.0
                distance_above = (current.close - upper) / band_width if band_width > 0 else 0.0
                confidence = min(1.0, 0.5 + distance_above)
                signals.append(
                    Signal(
                        side="BUY",
                        price=current.close,
                        time=current.timestamp,
                        type="entry",
                        confidence=confidence,
                    )
                )

        # SELL: close crosses below Lower band (only if RSI < 50 confirming downtrend)
        elif current.close < lower and rsi_curr < 50 and current.close < ema50_val:
            # Directional trend filter: only SELL if close < SMA
            if tf_val is not None and current.close >= tf_val:
                return signals
            if not volume_ok:
                return signals
            if prev_lower != prev_lower or candles[-2].close >= prev_lower:
                # Cross below — price was above or at lower, now below
                band_width = upper - lower if upper > lower else 1.0
                distance_below = (lower - current.close) / band_width if band_width > 0 else 0.0
                confidence = min(1.0, 0.5 + distance_below)
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
Keltner = KeltnerChannels
