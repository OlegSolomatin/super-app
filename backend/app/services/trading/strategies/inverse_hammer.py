"""Inverse Hammer candlestick pattern strategy with trend filter.

Logic:
    An Inverse Hammer is a single-candle bearish reversal pattern that
    appears during an uptrend.  Characteristics:
      - Small real body at the lower end of the candle
      - Long upper shadow (wick) — at least 2x the body length
      - Little to no lower shadow

    Trend filter (optional):
      - Only signals SELL if price is below SMA(period)
      - Prevents shorting into a strong uptrend

    Signal: SELL when an inverse hammer pattern is confirmed
            AND trend filter passes.
"""

from __future__ import annotations

from typing import List, Optional

from app.services.trading.models import Candle, Signal
from app.services.trading.strategies.base import AbstractStrategy


class InverseHammerStrategy(AbstractStrategy):
    """Inverse Hammer (bearish reversal) strategy with optional trend filter."""

    def __init__(
        self,
        trend_filter_enabled: bool = True,
        trend_filter_period: int = 200,
    ) -> None:
        super().__init__(name="inverse_hammer")
        self.trend_filter_enabled = trend_filter_enabled
        self.trend_filter_period = trend_filter_period

    @staticmethod
    def _compute_sma(candles: List[Candle], period: int) -> Optional[float]:
        """Compute SMA for the last `period` candles."""
        if len(candles) < period:
            return None
        total = sum(c.close for c in candles[-period:])
        return total / period

    def _check_trend_filter(self, candles: List[Candle]) -> bool:
        """Return True if trend filter passes or is disabled.

        For bearish signals: only SELL if price is BELOW SMA
        (confirming we're in a downtrend, so selling rallies is safe).
        """
        if not self.trend_filter_enabled:
            return True
        sma = self._compute_sma(candles, self.trend_filter_period)
        if sma is None:
            return True  # Not enough data — allow trade
        current_close = candles[-1].close
        return current_close < sma

    async def analyze(self, candles: List[Candle]) -> List[Signal]:
        """Analyze candles for Inverse Hammer patterns.

        Returns a SELL signal if the latest candle matches the Inverse
        Hammer criteria, the prior trend was up, AND the trend filter passes.
        """
        signals: List[Signal] = []

        if len(candles) < 3:
            return signals

        # Get the last two candles
        prev = candles[-2]
        current = candles[-1]

        # Check prior uptrend: previous candle close > previous open (bullish)
        prior_up = prev.close > prev.open

        if not prior_up:
            return signals

        # Trend filter: only SELL if price is below SMA
        if not self._check_trend_filter(candles):
            return signals

        # Inverse Hammer detection on current candle
        body = abs(current.close - current.open)
        upper_shadow = current.high - max(current.open, current.close)
        lower_shadow = min(current.open, current.close) - current.low

        # Criteria:
        # 1. Small body (not a doji — body > 0)
        # 2. Upper shadow >= 2x body length
        # 3. Lower shadow <= 0.3x body (little to no lower wick)
        if (
            body > 0
            and upper_shadow >= 2.0 * body
            and lower_shadow <= 0.3 * body
        ):
            entry_price = current.close
            signals.append(
                Signal(
                    side="SELL",
                    price=entry_price,
                    time=current.timestamp,
                    type="entry",
                    confidence=min(1.0, upper_shadow / (body * 3)),
                )
            )

        return signals


# Backward compatibility alias
InverseHammer = InverseHammerStrategy
