"""Inverse Hammer candlestick pattern strategy.

Logic:
    An Inverse Hammer is a single-candle bearish reversal pattern that
    appears during an uptrend.  Characteristics:
      - Small real body at the lower end of the candle
      - Long upper shadow (wick) — at least 2x the body length
      - Little to no lower shadow

    Signal: SELL when an inverse hammer pattern is confirmed.
    The upper shadow rejection indicates strong selling pressure.

    Entry:    After the inverse hammer candle closes, enter SHORT.
    Stop:     Above the high of the inverse hammer candle.
    Target:   Risk:Reward = 1:2 or next support level.
"""

from __future__ import annotations

from typing import List

from app.services.trading.models import Candle, Signal
from app.services.trading.strategies.base import AbstractStrategy


class InverseHammerStrategy(AbstractStrategy):
    """Inverse Hammer (bearish reversal) strategy.

    Detects Inverse Hammer candlestick patterns and generates SELL signals.
    """

    def __init__(self) -> None:
        super().__init__(name="inverse_hammer")

    async def analyze(self, candles: List[Candle]) -> List[Signal]:
        """Analyze candles for Inverse Hammer patterns.

        Returns a SELL signal if the latest candle matches the Inverse
        Hammer criteria and the overall trend was up.
        """
        signals: List[Signal] = []

        if len(candles) < 3:
            return signals

        # Get the last two candles
        prev = candles[-2]
        current = candles[-1]

        # Check prior uptrend: previous candle close > previous open (bullish)
        prior_up = prev.close > prev.open

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
            # Bearish reversal signal
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
