"""RSI Oversold / Overbought strategy.

Logic:
    BUY  when RSI(14) drops below 30 and stays below 30 for two consecutive
         candles — indicating a confirmed oversold condition.
    SELL when RSI(14) climbs above 70 and stays above 70 for two consecutive
         candles — indicating a confirmed overbought condition.

    Confidence is based on how extreme the RSI value is:
      - BUY:  1.0 - rsi / 100   (the lower the RSI, the higher the confidence)
      - SELL: rsi / 100         (the higher the RSI, the higher the confidence)
"""

from __future__ import annotations

from typing import List, Optional

from app.services.trading.models import Candle, Signal
from app.services.trading.strategies.base import AbstractStrategy
from app.services.trading.indicators.rsi import RSI


class RsiOversoldStrategy(AbstractStrategy):
    """RSI oversold / overbought strategy."""

    def __init__(
        self,
        trend_filter_enabled: bool = True,
        trend_filter_period: int = 200,
    ) -> None:
        super().__init__(name="rsi_oversold")
        self.trend_filter_enabled = trend_filter_enabled
        self.trend_filter_period = trend_filter_period

    async def analyze(self, candles: List[Candle]) -> List[Signal]:
        """Analyze candles for RSI oversold / overbought signals."""
        signals: List[Signal] = []
        min_candles = max(self.trend_filter_period, 15) if self.trend_filter_enabled else 15

        if len(candles) < min_candles:
            return signals

        rsi_indicator = RSI(period=14)
        rsi_values = rsi_indicator.compute(candles)

        if len(rsi_values) < 2:
            return signals

        rsi_prev = rsi_values[-2]
        rsi_curr = rsi_values[-1]

        # Skip if any value is NaN
        if rsi_prev != rsi_prev or rsi_curr != rsi_curr:
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

        # BUY: RSI < 25 with previous RSI also < 25 (confirmed oversold)
        if rsi_curr < 25 and rsi_prev < 25:
            confidence = 1.0 - rsi_curr / 100.0
            signals.append(
                Signal(
                    side="BUY",
                    price=current.close,
                    time=current.timestamp,
                    type="entry",
                    confidence=confidence,
                )
            )

        # SELL: RSI > 75 with previous RSI also > 75 (confirmed overbought)
        elif rsi_curr > 75 and rsi_prev > 75:
            confidence = rsi_curr / 100.0
            signals.append(
                Signal(
                    side="SELL",
                    price=current.close,
                    time=current.timestamp,
                    type="entry",
                    confidence=confidence,
                )
            )

        # Exit BUY when RSI recovers to 60
        if rsi_curr > 60 and rsi_prev <= 60:
            signals.append(
                Signal(
                    side="SELL",
                    price=current.close,
                    time=current.timestamp,
                    type="exit",
                    confidence=0.8,
                )
            )

        # Exit SELL when RSI drops to 40
        if rsi_curr < 40 and rsi_prev >= 40:
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
RsiOversold = RsiOversoldStrategy
