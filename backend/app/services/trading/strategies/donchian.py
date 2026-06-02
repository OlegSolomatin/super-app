"""Donchian Channels breakout strategy.

Logic:
    BUY  when close > highest high of last 20 candles (breakout up).
    SELL when close < lowest low of last 20 candles (breakout down).

    No external indicators are needed — looks back at a rolling window
    of price data.

    ATR(14) filter: only signals when current ATR > average ATR(20),
    ensuring volatility is high enough for a real breakout.

    Confidence is proportional to how far price is beyond the channel.
"""

from __future__ import annotations

from typing import List, Optional

from app.services.trading.models import Candle, Signal
from app.services.trading.strategies.base import AbstractStrategy
from app.services.trading.indicators.sma import SMA


class Donchian(AbstractStrategy):
    """Donchian Channels breakout strategy."""

    def __init__(
        self,
        trend_filter_enabled: bool = True,
        trend_filter_period: int = 200,
    ) -> None:
        super().__init__(name="donchian")
        self.trend_filter_enabled = trend_filter_enabled
        self.trend_filter_period = trend_filter_period

    async def analyze(self, candles: List[Candle]) -> List[Signal]:
        """Analyze candles for Donchian breakout signals."""
        signals: List[Signal] = []
        period = 20
        min_candles = period + 1

        if len(candles) < min_candles:
            return signals

        current = candles[-1]

        # Compute ATR(14) inline for volatility filter
        tr_values: List[float] = []
        for i in range(len(candles)):
            if i == 0:
                tr_values.append(candles[i].high - candles[i].low)
            else:
                hl = candles[i].high - candles[i].low
                hc = abs(candles[i].high - candles[i - 1].close)
                lc = abs(candles[i].low - candles[i - 1].close)
                tr_values.append(max(hl, hc, lc))
        sma_tr = SMA(period=14)
        fake = [Candle(open=0, high=0, low=0, close=v, volume=0, timestamp=c.timestamp) for v, c in zip(tr_values, candles)]
        atr_vals = sma_tr.compute(fake)
        atr_curr = atr_vals[-1]
        # ATR SMA for comparison
        atr_sma = SMA(period=20)
        atr_avg_vals = atr_sma.compute(fake)
        atr_avg = atr_avg_vals[-1]
        if atr_curr != atr_curr or atr_avg != atr_avg:
            return signals
        if atr_curr <= atr_avg:
            return signals  # need higher than average volatility

        # Trend filter: only BUY if price is above long-term SMA
        if self.trend_filter_enabled:
            sma_tf = SMA(period=self.trend_filter_period)
            tf_vals = sma_tf.compute(candles)
            tf_val = tf_vals[-1]
            if tf_val != tf_val:
                return signals
            if current.close <= tf_val:
                return signals

        # Look back at the last `period` candles (excluding current)
        window = candles[-(period + 1):-1]
        highest_high = max(c.high for c in window)
        lowest_low = min(c.low for c in window)

        channel_width = highest_high - lowest_low if highest_high > lowest_low else 1.0

        # BUY: close breaks above the highest high
        if current.close > highest_high:
            distance_above = (current.close - highest_high) / channel_width if channel_width > 0 else 0.0
            confidence = min(1.0, 0.5 + distance_above)
            signals.append(
                Signal(
                    side="BUY",
                    price=current.close,
                    time=current.timestamp,
                    type="entry",
                    confidence=confidence,
                )
            )

        # SELL: close breaks below the lowest low
        elif current.close < lowest_low:
            distance_below = (lowest_low - current.close) / channel_width if channel_width > 0 else 0.0
            confidence = min(1.0, 0.5 + distance_below)
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
DonchianChannels = Donchian
