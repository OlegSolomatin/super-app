"""Doji Detection strategy.

Logic:
    A doji is a candle where the body (|open - close|) is less than 5% of
    the total range (high - low), indicating indecision.

    BUY:  doji formed after 2+ consecutive bearish candles (close < open)
          — potential reversal to the upside.
    SELL: doji formed after 2+ consecutive bullish candles (close > open)
          — potential reversal to the downside.

    Confidence scales with the number of preceding consecutive candles:
      - 2 preceding candles: base confidence
      - Each additional candle adds more conviction
"""

from __future__ import annotations

from typing import List, Optional

from app.services.trading.models import Candle, Signal
from app.services.trading.strategies.base import AbstractStrategy


class DojiStrategy(AbstractStrategy):
    """Doji reversal detection strategy."""

    def __init__(
        self,
        trend_filter_enabled: bool = True,
        trend_filter_period: int = 200,
    ) -> None:
        super().__init__(name="doji")
        self.trend_filter_enabled = trend_filter_enabled
        self.trend_filter_period = trend_filter_period

    async def analyze(self, candles: List[Candle]) -> List[Signal]:
        """Analyze candles for doji reversal patterns."""
        signals: List[Signal] = []
        min_candles = max(self.trend_filter_period, 3) if self.trend_filter_enabled else 3

        if len(candles) < min_candles:
            return signals

        current = candles[-1]

        # Determine if current candle is a doji
        body = abs(current.close - current.open)
        total_range = current.high - current.low
        is_doji = total_range > 0 and (body / total_range) < 0.03

        if not is_doji:
            return signals

        # Count consecutive bearish candles before current
        bearish_count = 0
        for c in reversed(candles[:-1]):
            if c.close < c.open:
                bearish_count += 1
            else:
                break

        # Count consecutive bullish candles before current
        bullish_count = 0
        for c in reversed(candles[:-1]):
            if c.close > c.open:
                bullish_count += 1
            else:
                break

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

        # BUY: doji after 2+ bearish candles (potential reversal up)
        if bearish_count >= 2:
            confidence = min(1.0, 0.5 + (bearish_count - 2) * 0.15)
            signals.append(
                Signal(
                    side="BUY",
                    price=current.close,
                    time=current.timestamp,
                    type="entry",
                    confidence=confidence,
                )
            )

        # SELL: doji after 2+ bullish candles (potential reversal down)
        elif bullish_count >= 2:
            confidence = min(1.0, 0.5 + (bullish_count - 2) * 0.15)
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
Doji = DojiStrategy
