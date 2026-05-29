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
        # TODO: implement full candle pattern recognition logic
        signals: List[Signal] = []
        # Placeholder — will be replaced with real pattern detection
        return signals
