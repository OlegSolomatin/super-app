"""Hammer candlestick pattern strategy with trend filter.

Logic:
    A Hammer is a single-candle bullish reversal pattern that appears
    during a downtrend.  Characteristics:
      - Small real body at the upper end of the candle
      - Long lower shadow (wick) — at least 2x the body length
      - Little to no upper shadow

    Trend filter (optional):
      - Only signals BUY if price is above SMA(period)
      - Prevents buying into a strong downtrend

    Signal: BUY when a hammer pattern is confirmed AND trend filter passes.
"""

from __future__ import annotations

from typing import List, Optional

from app.services.trading.models import Candle, Signal, TradingConfig
from app.services.trading.strategies.base import AbstractStrategy


class HammerStrategy(AbstractStrategy):
    """Hammer (bullish reversal) strategy with optional trend filter."""

    def __init__(
        self,
        trend_filter_enabled: bool = True,
        trend_filter_period: int = 200,
    ) -> None:
        super().__init__(name="hammer")
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
        """Return True if trend filter passes or is disabled."""
        if not self.trend_filter_enabled:
            return True
        sma = self._compute_sma(candles, self.trend_filter_period)
        if sma is None:
            return True  # Not enough data — allow trade
        current_close = candles[-1].close
        return current_close > sma

    async def analyze(self, candles: List[Candle]) -> List[Signal]:
        """Analyze candles for Hammer patterns.

        Returns a BUY signal if the latest candle matches the Hammer
        criteria, the prior trend was down, AND the trend filter passes.
        """
        signals: List[Signal] = []

        if len(candles) < 3:
            return signals

        # Get the last two candles
        prev = candles[-2]
        current = candles[-1]

        # Check prior downtrend: previous candle close < previous open (bearish)
        prior_down = prev.close < prev.open

        if not prior_down:
            return signals

        # Trend filter: only BUY if price is above SMA
        if not self._check_trend_filter(candles):
            return signals

        # Hammer detection on current candle
        body = abs(current.close - current.open)
        lower_shadow = min(current.open, current.close) - current.low
        upper_shadow = current.high - max(current.open, current.close)

        # Criteria:
        # 1. Small body (not a doji — body > 0)
        # 2. Lower shadow >= 2x body length
        # 3. Upper shadow <= 0.3x body (little to no upper wick)
        if (
            body > 0
            and lower_shadow >= 2.0 * body
            and upper_shadow <= 0.3 * body
        ):
            entry_price = current.close
            signals.append(
                Signal(
                    side="BUY",
                    price=entry_price,
                    time=current.timestamp,
                    type="entry",
                    confidence=min(1.0, lower_shadow / (body * 3)),
                )
            )

        return signals


# Backward compatibility alias
Hammer = HammerStrategy
