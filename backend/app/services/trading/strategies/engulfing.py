"""Bullish / Bearish Engulfing strategy.

Logic:
    A bullish engulfing pattern occurs when a green candle (close > open)
    completely engulfs the body of the previous red candle (close < open).

    A bearish engulfing pattern occurs when a red candle (close < open)
    completely engulfs the body of the previous green candle (close > open).

    Body engulfing means:
        current.open <= previous.close  AND  current.close >= previous.open   (bullish)
        current.open >= previous.close  AND  current.close <= previous.open   (bearish)

    Trend filter is directional:
      - BUY:  close > SMA(trend_filter_period) — only buy in uptrend
      - SELL: close < SMA(trend_filter_period) — only sell in downtrend

    Volume confirmation: current volume must exceed previous candle volume.

    exit_target = candle_range (high - low) as in Hammer strategy.
    Confidence is based on the ratio of the current body size to the previous body size.
"""

from __future__ import annotations

from typing import List, Optional

from app.services.trading.models import Candle, Signal
from app.services.trading.strategies.base import AbstractStrategy
from app.services.trading.indicators.sma import SMA


class EngulfingStrategy(AbstractStrategy):
    """Bullish / Bearish Engulfing strategy."""

    def __init__(
        self,
        trend_filter_enabled: bool = True,
        trend_filter_period: int = 200,
        min_engulf_ratio: float = 1.0,
    ) -> None:
        super().__init__(name="engulfing")
        self.trend_filter_enabled = trend_filter_enabled
        self.trend_filter_period = trend_filter_period
        self.min_engulf_ratio = min_engulf_ratio

    async def analyze(self, candles: List[Candle]) -> List[Signal]:
        """Analyze candles for engulfing patterns."""
        signals: List[Signal] = []
        min_candles = max(self.trend_filter_period, 3) if self.trend_filter_enabled else 3

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

        # Trend filter SMA
        tf_val: Optional[float] = None
        if self.trend_filter_enabled:
            sma_tf = SMA(period=self.trend_filter_period)
            tf_vals = sma_tf.compute(candles)
            tf_val = tf_vals[-1]
            if tf_val is not None and tf_val != tf_val:
                return signals

        # Volume confirmation: current volume must be > previous candle volume
        if current.volume <= prev.volume:
            return signals

        candle_range = current.high - current.low

        # BUY: bullish engulfing — previous was bearish, body engulfs, current is bullish
        if (
            prev.close < prev.open  # previous was bearish
            and current.open <= prev.close  # current opens at or below previous close
            and current.close >= prev.open  # current closes at or above previous open
            and current.close > current.open  # current is bullish
        ):
            # Check minimum engulf ratio
            ratio = curr_body_size / prev_body_size if prev_body_size > 0 else self.min_engulf_ratio
            if ratio < self.min_engulf_ratio:
                return signals
            # Directional trend filter: only BUY if close > SMA
            if tf_val is not None and current.close <= tf_val:
                return signals
            confidence = min(1.0, ratio)
            signals.append(
                Signal(
                    side="BUY",
                    price=current.close,
                    time=current.timestamp,
                    type="entry",
                    confidence=confidence,
                    exit_target=current.close + candle_range,
                )
            )

        # SELL: bearish engulfing — previous was bullish, body engulfs, current is bearish
        elif (
            prev.close > prev.open  # previous was bullish
            and current.open >= prev.close  # current opens at or above previous close
            and current.close <= prev.open  # current closes at or below previous open
            and current.close < current.open  # current is bearish
        ):
            ratio = curr_body_size / prev_body_size if prev_body_size > 0 else self.min_engulf_ratio
            if ratio < self.min_engulf_ratio:
                return signals
            # Directional trend filter: only SELL if close < SMA
            if tf_val is not None and current.close >= tf_val:
                return signals
            confidence = min(1.0, ratio)
            signals.append(
                Signal(
                    side="SELL",
                    price=current.close,
                    time=current.timestamp,
                    type="entry",
                    confidence=confidence,
                    exit_target=current.close - candle_range,
                )
            )

        return signals


# Backward compatibility alias
Engulfing = EngulfingStrategy
