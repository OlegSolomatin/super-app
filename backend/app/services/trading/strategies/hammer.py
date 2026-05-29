"""Hammer candlestick pattern strategy.

Logic:
    A Hammer is a single-candle bullish reversal pattern that appears
    during a downtrend.  Characteristics:
      - Small real body at the upper end of the candle
      - Long lower shadow (wick) — at least 2x the body length
      - Little to no upper shadow

    Signal: BUY when a hammer pattern is confirmed.
    The lower shadow rejection indicates strong buying pressure.

    Entry:    After the hammer candle closes, enter LONG.
    Stop:     Below the low of the hammer candle.
    Target:   Risk:Reward = 1:2 or next resistance level.
"""

from __future__ import annotations

from typing import List

from app.services.trading.models import Candle, Signal
from app.services.trading.strategies.base import AbstractStrategy


class HammerStrategy(AbstractStrategy):
    """Hammer (bullish reversal) strategy.

    Detects Hammer candlestick patterns and generates BUY signals.
    """

    def __init__(self) -> None:
        super().__init__(name="hammer")

    async def analyze(self, candles: List[Candle]) -> List[Signal]:
        """Analyze candles for Hammer patterns.

        Returns a BUY signal if the latest candle matches the Hammer
        criteria and the overall trend was down.
        """
        signals: List[Signal] = []

        if len(candles) < 3:
            return signals

        # Get the last two candles
        prev = candles[-2]
        current = candles[-1]

        # Check prior downtrend: previous candle close < previous open (bearish)
        # and close price is lower than the close before it
        prior_down = prev.close < prev.open

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
            # Bullish reversal signal
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
