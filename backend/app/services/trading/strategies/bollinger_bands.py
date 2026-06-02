"""Bollinger Bands Reversal strategy.

Logic:
    BUY  when the price touches or crosses below the lower band (oversold bounce).
    SELL when the price touches or crosses above the upper band (overbought pullback).

    Uses standard Bollinger Bands configuration: period=20, k=2.

    Confidence is based on how far the price is beyond the band:
      - BUY:  how far below the lower band (normalised by band width), capped at 1.0
      - SELL: how far above the upper band (normalised by band width), capped at 1.0
"""

from __future__ import annotations

from typing import List, Optional

from app.services.trading.models import Candle, Signal
from app.services.trading.strategies.base import AbstractStrategy
from app.services.trading.indicators.bollinger import BollingerBands


class BollingerBandsStrategy(AbstractStrategy):
    """Bollinger Bands reversal strategy."""

    def __init__(
        self,
        trend_filter_enabled: bool = True,
        trend_filter_period: int = 200,
    ) -> None:
        super().__init__(name="bollinger_bands")
        self.trend_filter_enabled = trend_filter_enabled
        self.trend_filter_period = trend_filter_period

    async def analyze(self, candles: List[Candle]) -> List[Signal]:
        """Analyze candles for Bollinger Bands reversal signals."""
        signals: List[Signal] = []
        min_candles = max(self.trend_filter_period, 21) if self.trend_filter_enabled else 21

        if len(candles) < min_candles:
            return signals

        bb_indicator = BollingerBands(period=20, k=2.0)
        bb_values = bb_indicator.compute(candles)

        if len(bb_values) < 2:
            return signals

        upper_curr, middle_curr, lower_curr = bb_values[-1]
        upper_prev, middle_prev, lower_prev = bb_values[-2]

        # Skip if any value is NaN
        if any(v != v for v in (upper_curr, middle_curr, lower_curr)):
            return signals

        current = candles[-1]

        # Trend filter: only BUY if price is above long-term SMA
        if self.trend_filter_enabled:
            from app.services.trading.indicators.sma import SMA

            sma_tf = SMA(period=self.trend_filter_period)
            tf_vals = sma_tf.compute(candles)
            tf_val = tf_vals[-1]
            if tf_val != tf_val:
                return signals
            if current.close <= tf_val:
                return signals

        band_width = upper_curr - lower_curr

        # SMA(50) trend filter: BUY only in uptrend, SELL only in downtrend
        from app.services.trading.indicators.sma import SMA
        sma50 = SMA(period=50)
        sma50_vals = sma50.compute(candles)
        sma50_val = sma50_vals[-1]
        if sma50_val != sma50_val:
            return signals

        # BUY: price touches or crosses below lower band (oversold bounce in uptrend)
        if current.close <= lower_curr and current.close > sma50_val:
            # Check for touch/cross (either current is below, or crossed from above)
            prev_above_lower = upper_prev  # just check that previous existed (not NaN)
            if prev_above_lower == prev_above_lower:  # not NaN
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

        # SELL: price touches or crosses above upper band (overbought pullback in downtrend)
        elif current.close >= upper_curr and current.close < sma50_val:
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

        return signals


# Backward compatibility alias
BBReversal = BollingerBandsStrategy
