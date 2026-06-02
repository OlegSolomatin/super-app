"""Bullish / Bearish Engulfing strategy.

Logic:
    A bullish engulfing pattern occurs when a green candle (close > open)
    completely engulfs the body of the previous red candle (close < open).

    A bearish engulfing pattern occurs when a red candle (close < open)
    completely engulfs the body of the previous green candle (close > open).

    Body engulfing means:
        current.open <= previous.close  AND  current.close >= previous.open   (bullish)
        current.open >= previous.close  AND  current.close <= previous.open   (bearish)

    Confidence is based on the ratio of the current body size to the previous
    body size, capped at 1.0.
"""

from __future__ import annotations

from typing import List, Optional

from app.services.trading.models import Candle, Signal
from app.services.trading.strategies.base import AbstractStrategy


class EngulfingStrategy(AbstractStrategy):
    """Bullish / Bearish Engulfing strategy."""

    def __init__(
        self,
        trend_filter_enabled: bool = True,
        trend_filter_period: int = 200,
    ) -> None:
        super().__init__(name="engulfing")
        self.trend_filter_enabled = trend_filter_enabled
        self.trend_filter_period = trend_filter_period

    async def analyze(self, candles: List[Candle]) -> List[Signal]:
        """Analyze candles for engulfing patterns."""
        signals: List[Signal] = []
        min_candles = max(self.trend_filter_period, 2) if self.trend_filter_enabled else 2

        if len(candles) < min_candles:
            return signals

        if len(candles) < 2:
            return signals

        prev = candles[-2]
        current = candles[-1]

        prev_body_top = max(prev.open, prev.close)
        prev_body_bottom = min(prev.open, prev.close)
        curr_body_top = max(current.open, current.close)
        curr_body_bottom = min(current.open, current.close)
        prev_body_size = prev_body_top - prev_body_bottom
        curr_body_size = curr_body_top - curr_body_bottom

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

        # Volume confirmation: current volume must be > previous candle volume
        if current.volume <= prev.volume:
            return signals

        # BUY: bullish engulfing — previous was bearish, current body engulfs previous body, current is bullish
        if (
            prev.close < prev.open  # previous was bearish
            and current.open <= prev.close  # current opens at or below previous close
            and current.close >= prev.open  # current closes at or above previous open
            and current.close > current.open  # current is bullish
        ):
            confidence = min(1.0, curr_body_size / prev_body_size) if prev_body_size > 0 else 0.5
            signals.append(
                Signal(
                    side="BUY",
                    price=current.close,
                    time=current.timestamp,
                    type="entry",
                    confidence=confidence,
                )
            )

        # SELL: bearish engulfing — previous was bullish, current body engulfs previous body, current is bearish
        elif (
            prev.close > prev.open  # previous was bullish
            and current.open >= prev.close  # current opens at or above previous close
            and current.close <= prev.open  # current closes at or below previous open
            and current.close < current.open  # current is bearish
        ):
            confidence = min(1.0, curr_body_size / prev_body_size) if prev_body_size > 0 else 0.5
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
Engulfing = EngulfingStrategy
