"""All-Pairs Inverse Hammer Scanner — scans EVERY available pair.

Logic:
    Identical to the regular Inverse Hammer strategy, but runs across
    ALL USDT pairs available on the exchange.  Only works in history
    mode with TF >= 30m to avoid overloading the server.
"""

from __future__ import annotations

from typing import List, Optional

from app.services.trading.models import Candle, Signal
from app.services.trading.strategies.base import AbstractStrategy


class AllPairsInverseHammerStrategy(AbstractStrategy):
    """Inverse Hammer scanner that checks all available pairs (history only)."""

    is_pair_scanner = True

    def __init__(
        self,
        trend_filter_enabled: bool = True,
        trend_filter_period: int = 50,
    ) -> None:
        super().__init__(name="all_pairs_inverse_hammer")
        self.trend_filter_enabled = trend_filter_enabled
        self.trend_filter_period = trend_filter_period

    @staticmethod
    def _compute_sma(candles: List[Candle], period: int) -> Optional[float]:
        if len(candles) < period:
            return None
        total = sum(c.close for c in candles[-period:])
        return total / period

    def _check_trend_filter(self, candles: List[Candle]) -> bool:
        """Only SELL if price is BELOW SMA (confirming downtrend)."""
        if not self.trend_filter_enabled:
            return True
        sma = self._compute_sma(candles, self.trend_filter_period)
        if sma is None:
            return True
        current_close = candles[-1].close
        return current_close < sma

    async def analyze(self, candles: List[Candle]) -> List[Signal]:
        """Analyze candles for Inverse Hammer patterns."""
        signals: List[Signal] = []

        if len(candles) < 3:
            return signals

        prev = candles[-2]
        current = candles[-1]

        # Prior uptrend: previous candle was bullish
        if not (prev.close > prev.open):
            return signals

        # Trend filter: only SELL if price is below SMA
        if not self._check_trend_filter(candles):
            return signals

        # Inverse Hammer detection
        body = abs(current.close - current.open)
        upper_shadow = current.high - max(current.open, current.close)
        lower_shadow = min(current.open, current.close) - current.low

        if (
            body > 0
            and upper_shadow >= 2.0 * body
            and lower_shadow <= 0.3 * body
        ):
            entry_price = current.close
            # Dynamic TP: full candle range (high-low) from entry (for SELL: entry - range)
            candle_range = current.high - current.low
            exit_target = entry_price - candle_range
            signals.append(
                Signal(
                    side="SELL",
                    price=entry_price,
                    time=current.timestamp,
                    type="entry",
                    confidence=min(1.0, upper_shadow / (body * 3)),
                    exit_target=exit_target,
                )
            )

        return signals
