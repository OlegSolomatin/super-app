"""Bollinger Bands Reversal strategy.

Logic:
    BUY  when the price touches or crosses below the lower band (oversold bounce)
         in an uptrend (close > SMA50 AND close > SMA(trend_filter_period)).
    SELL when the price touches or crosses above the upper band (overbought pullback)
         in a downtrend (close < SMA50 AND close < SMA(trend_filter_period)).

    Volume confirmation: current volume must exceed average of last 5 candles.

    Exit signal: price returns to the middle band (mean reversion complete).

    Confidence is based on how far the price is beyond the band.
    exit_target is calculated dynamically by the engine (entry ± ATR×2).
"""

from __future__ import annotations

from typing import List, Optional

from app.services.trading.models import Candle, Signal
from app.services.trading.strategies.base import AbstractStrategy
from app.services.trading.indicators.bollinger import BollingerBands
from app.services.trading.indicators.sma import SMA


class BollingerBandsStrategy(AbstractStrategy):
    """Bollinger Bands reversal strategy."""

    def __init__(
        self,
        trend_filter_enabled: bool = True,
        trend_filter_period: int = 200,
        bb_period: int = 20,
        bb_std: float = 2.0,
    ) -> None:
        super().__init__(name="bollinger_bands")
        self.trend_filter_enabled = trend_filter_enabled
        self.trend_filter_period = trend_filter_period
        self.bb_period = bb_period
        self.bb_std = bb_std

    async def analyze(self, candles: List[Candle]) -> List[Signal]:
        """Analyze candles for Bollinger Bands reversal signals."""
        signals: List[Signal] = []
        min_candles = max(self.trend_filter_period, self.bb_period + 5) if self.trend_filter_enabled else self.bb_period + 5

        if len(candles) < min_candles:
            return signals

        bb_indicator = BollingerBands(period=self.bb_period, k=self.bb_std)
        bb_values = bb_indicator.compute(candles)

        if len(bb_values) < 2:
            return signals

        upper_curr, middle_curr, lower_curr = bb_values[-1]
        upper_prev, middle_prev, lower_prev = bb_values[-2]

        # Skip if any value is NaN
        if any(v != v for v in (upper_curr, middle_curr, lower_curr)):
            return signals

        current = candles[-1]

        # Long-term trend filter SMA
        tf_val: Optional[float] = None
        if self.trend_filter_enabled:
            sma_tf = SMA(period=self.trend_filter_period)
            tf_vals = sma_tf.compute(candles)
            tf_val = tf_vals[-1]
            if tf_val is not None and tf_val != tf_val:
                return signals

        # SMA(50) directional short-term filter
        sma50 = SMA(period=50)
        sma50_vals = sma50.compute(candles)
        sma50_val = sma50_vals[-1]
        if sma50_val != sma50_val:
            return signals

        # Volume confirmation
        if len(candles) >= 6:
            avg_vol = sum(c.volume for c in candles[-6:-1]) / 5.0
            volume_ok = current.volume > avg_vol
        else:
            volume_ok = True

        band_width = upper_curr - lower_curr

        # BUY: price touches or crosses below lower band in uptrend
        if current.close <= lower_curr and current.close > sma50_val:
            # Long-term trend filter: only BUY if close > SMA
            if tf_val is not None and current.close <= tf_val:
                return signals
            if not volume_ok:
                return signals
            distance_below = (lower_curr - current.close) / band_width if band_width > 0 else 0.0
            confidence = min(1.0, 0.5 + distance_below)
            signals.append(
                Signal(
                    side="BUY",
                    price=current.close,
                    time=current.timestamp,
                    type="entry",
                    confidence=confidence,
                )
            )

        # SELL: price touches or crosses above upper band in downtrend
        elif current.close >= upper_curr and current.close < sma50_val:
            # Long-term trend filter: only SELL if close < SMA
            if tf_val is not None and current.close >= tf_val:
                return signals
            if not volume_ok:
                return signals
            distance_above = (current.close - upper_curr) / band_width if band_width > 0 else 0.0
            confidence = min(1.0, 0.5 + distance_above)
            signals.append(
                Signal(
                    side="SELL",
                    price=current.close,
                    time=current.timestamp,
                    type="entry",
                    confidence=confidence,
                )
            )

        # Exit signal: price returns to middle band (from either side)
        prev_above_middle = candles[-2].close > middle_prev
        curr_above_middle = current.close > middle_curr
        if prev_above_middle != curr_above_middle:
            if curr_above_middle:
                signals.append(
                    Signal(
                        side="BUY",
                        price=current.close,
                        time=current.timestamp,
                        type="exit",
                        confidence=0.7,
                    )
                )
            else:
                signals.append(
                    Signal(
                        side="SELL",
                        price=current.close,
                        time=current.timestamp,
                        type="exit",
                        confidence=0.7,
                    )
                )

        return signals


# Backward compatibility alias
BBReversal = BollingerBandsStrategy
