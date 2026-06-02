"""Three White Soldiers / Three Black Crows strategy.

Logic:
    Three White Soldiers (BUY):
      3 consecutive bullish candles (close > open) where each close is
      higher than the previous close — a strong bullish continuation pattern.

    Three Black Crows (SELL):
      3 consecutive bearish candles (close < open) where each close is
      lower than the previous close — a strong bearish continuation pattern.

    Confidence is based on the average body-to-range ratio of the three candles
    (stronger confidence when bodies are large relative to the wicks).
"""

from __future__ import annotations

from typing import List, Optional

from app.services.trading.models import Candle, Signal
from app.services.trading.strategies.base import AbstractStrategy


class ThreeSoldiersStrategy(AbstractStrategy):
    """Three White Soldiers / Three Black Crows strategy."""

    def __init__(
        self,
        trend_filter_enabled: bool = True,
        trend_filter_period: int = 200,
    ) -> None:
        super().__init__(name="three_soldiers")
        self.trend_filter_enabled = trend_filter_enabled
        self.trend_filter_period = trend_filter_period

    async def analyze(self, candles: List[Candle]) -> List[Signal]:
        """Analyze candles for three-soldiers / three-crows patterns."""
        signals: List[Signal] = []
        min_candles = max(self.trend_filter_period, 3) if self.trend_filter_enabled else 3

        if len(candles) < min_candles:
            return signals

        if len(candles) < 3:
            return signals

        c1 = candles[-3]
        c2 = candles[-2]
        c3 = candles[-1]

        # Check Three White Soldiers (BUY): 3 bullish candles with rising closes
        bull_soldiers = (
            c1.close > c1.open
            and c2.close > c2.open
            and c3.close > c3.open
            and c1.close < c2.close
            and c2.close < c3.close
        )

        # Check Three Black Crows (SELL): 3 bearish candles with falling closes
        bear_crows = (
            c1.close < c1.open
            and c2.close < c2.open
            and c3.close < c3.open
            and c1.close > c2.close
            and c2.close > c3.close
        )

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

        if bull_soldiers:
            # Confidence based on average body-to-range ratio of the 3 candles
            ratios = []
            for c in (c1, c2, c3):
                rng = c.high - c.low
                if rng > 0:
                    ratios.append(abs(c.close - c.open) / rng)
                else:
                    ratios.append(0.5)
            avg_ratio = sum(ratios) / len(ratios)
            confidence = min(1.0, 0.6 + avg_ratio * 0.4)
            signals.append(
                Signal(
                    side="BUY",
                    price=current.close,
                    time=current.timestamp,
                    type="entry",
                    confidence=confidence,
                )
            )

        elif bear_crows:
            ratios = []
            for c in (c1, c2, c3):
                rng = c.high - c.low
                if rng > 0:
                    ratios.append(abs(c.close - c.open) / rng)
                else:
                    ratios.append(0.5)
            avg_ratio = sum(ratios) / len(ratios)
            confidence = min(1.0, 0.6 + avg_ratio * 0.4)
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
ThreeSoldiers = ThreeSoldiersStrategy
