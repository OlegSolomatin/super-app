"""All-Pairs Hammer Scanner — scans EVERY available pair for hammer patterns.

Logic:
    Identical to the regular Hammer strategy, but runs across ALL USDT
    pairs available on the exchange.  Only works in history mode with
    TF >= 30m to avoid overloading the server.

    Each trade records which pair it came from in Trade.pair.
"""

from __future__ import annotations

from typing import List, Optional

from app.services.trading.models import Candle, Signal
from app.services.trading.strategies.base import AbstractStrategy


class AllPairsHammerStrategy(AbstractStrategy):
    """Hammer scanner that checks all available pairs (history only)."""

    # Flag for the engine/scheduler to know we need multi-pair execution
    is_pair_scanner = True

    def __init__(
        self,
        trend_filter_enabled: bool = True,
        trend_filter_period: int = 50,
    ) -> None:
        super().__init__(name="all_pairs_hammer")
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
        """Analyze candles for Hammer patterns (same logic as HammerStrategy).

        Returns a BUY signal if the latest candle matches the Hammer
        criteria, the prior trend was down, AND the trend filter passes.
        """
        signals: List[Signal] = []

        if len(candles) < 4:
            return signals

        # Get the current and two prior candles
        current = candles[-1]
        c2 = candles[-2]
        c3 = candles[-3]

        # Check prior downtrend: 2 prior candles must be bearish (was 3)
        if not (c3.close < c3.open and c2.close < c2.open):
            return signals

        # Trend filter: only BUY if price is above SMA
        if not self._check_trend_filter(candles):
            return signals

        # Hammer detection
        body = abs(current.close - current.open)
        lower_shadow = min(current.open, current.close) - current.low
        upper_shadow = current.high - max(current.open, current.close)

        if (
            body > 0
            and lower_shadow >= 2.0 * body
            and upper_shadow <= 0.3 * body
        ):
            # Volume filter
            if len(candles) >= 11:
                avg_vol = sum(c.volume for c in candles[-6:-1]) / 5.0
                if current.volume <= avg_vol:
                    return signals

            entry_price = current.close
            # Dynamic TP: full candle range (high-low) from entry
            candle_range = current.high - current.low
            exit_target = entry_price + candle_range
            signals.append(
                Signal(
                    side="BUY",
                    price=entry_price,
                    time=current.timestamp,
                    type="entry",
                    confidence=min(1.0, lower_shadow / (body * 3)),
                    exit_target=exit_target,
                )
            )

        return signals
