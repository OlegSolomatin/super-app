"""Donchian Channels breakout strategy.

Logic:
    BUY  when close > highest high of last `donchian_period` candles (breakout up).
    SELL when close < lowest low of last `donchian_period` candles (breakout down).

    ATR volatility filter: only signals when current ATR > average ATR over
    `atr_comparison_period`, ensuring volatility is high enough for a real breakout.

    Trend filter is directional:
      - BUY:  close > SMA(trend_filter_period)
      - SELL: close < SMA(trend_filter_period)

    Volume confirmation: current volume must exceed average of last 5 candles.

    Exit signal: price returns inside the channel (no longer at extreme).

    Confidence is proportional to how far price is beyond the channel.
    exit_target is calculated dynamically by the engine (entry ± ATR×2).
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
        donchian_period: int = 20,
        atr_period: int = 14,
        atr_comparison_period: int = 20,
    ) -> None:
        super().__init__(name="donchian")
        self.trend_filter_enabled = trend_filter_enabled
        self.trend_filter_period = trend_filter_period
        self.donchian_period = donchian_period
        self.atr_period = atr_period
        self.atr_comparison_period = atr_comparison_period

    async def analyze(self, candles: List[Candle]) -> List[Signal]:
        """Analyze candles for Donchian breakout signals."""
        signals: List[Signal] = []
        min_candles = self.donchian_period + self.atr_period + 5

        if len(candles) < min_candles:
            return signals

        current = candles[-1]
        prev = candles[-2]

        # Trend filter SMA
        tf_val: Optional[float] = None
        if self.trend_filter_enabled:
            sma_tf = SMA(period=self.trend_filter_period)
            tf_vals = sma_tf.compute(candles)
            tf_val = tf_vals[-1]
            if tf_val is not None and tf_val != tf_val:
                return signals

        # Volume confirmation
        if len(candles) >= 6:
            avg_vol = sum(c.volume for c in candles[-6:-1]) / 5.0
            volume_ok = current.volume > avg_vol
        else:
            volume_ok = True

        # Look back at the last `donchian_period` candles (excluding current)
        window = candles[-(self.donchian_period + 1):-1]
        highest_high = max(c.high for c in window)
        lowest_low = min(c.low for c in window)
        channel_width = highest_high - lowest_low if highest_high > lowest_low else 1.0

        # BUY: close breaks above the highest high
        if current.close > highest_high:
            # ATR volatility filter
            if not self._check_atr_filter(candles):
                return signals
            # Directional trend filter: only BUY if close > SMA
            if tf_val is not None and current.close <= tf_val:
                return signals
            if not volume_ok:
                return signals
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
            if not self._check_atr_filter(candles):
                return signals
            # Directional trend filter: only SELL if close < SMA
            if tf_val is not None and current.close >= tf_val:
                return signals
            if not volume_ok:
                return signals
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

        # Exit signal: price returns inside channel (was outside, now inside)
        if prev.close > highest_high and current.close <= highest_high:
            signals.append(
                Signal(
                    side="SELL",
                    price=current.close,
                    time=current.timestamp,
                    type="exit",
                    confidence=0.7,
                )
            )
        elif prev.close < lowest_low and current.close >= lowest_low:
            signals.append(
                Signal(
                    side="BUY",
                    price=current.close,
                    time=current.timestamp,
                    type="exit",
                    confidence=0.7,
                )
            )

        return signals

    def _check_atr_filter(self, candles: List[Candle]) -> bool:
        """Check if current ATR is above average ATR (volatility filter).

        Returns True if volatility is high enough for a meaningful breakout.
        """
        tr_values: List[float] = []
        for i in range(len(candles)):
            if i == 0:
                tr_values.append(candles[i].high - candles[i].low)
            else:
                hl = candles[i].high - candles[i].low
                hc = abs(candles[i].high - candles[i - 1].close)
                lc = abs(candles[i].low - candles[i - 1].close)
                tr_values.append(max(hl, hc, lc))

        fake = [
            Candle(open=0, high=0, low=0, close=v, volume=0, timestamp=c.timestamp)
            for v, c in zip(tr_values, candles)
        ]
        sma_tr = SMA(period=self.atr_period)
        atr_vals = sma_tr.compute(fake)
        atr_curr = atr_vals[-1]
        atr_avg_sma = SMA(period=self.atr_comparison_period)
        atr_avg_vals = atr_avg_sma.compute(fake)
        atr_avg = atr_avg_vals[-1]

        if atr_curr != atr_curr or atr_avg != atr_avg:
            return False
        return atr_curr > atr_avg


# Backward compatibility alias
DonchianChannels = Donchian
