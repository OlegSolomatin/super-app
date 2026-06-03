"""VWAP (Volume Weighted Average Price) strategy.

Logic:
    VWAP = sum(typical_price * volume) / sum(volume) for the session.
    Typical price = (high + low + close) / 3.

    BUY  when close < VWAP * (1 - deviation_pct) AND close > SMA(50)
         (dip below VWAP in short-term uptrend = mean reversion buy).
    SELL when close > VWAP * (1 + deviation_pct) AND close < SMA(50)
         (rally above VWAP in short-term downtrend = mean reversion sell).

    Trend filter is directional:
      - BUY:  close > SMA(trend_filter_period) — long-term uptrend
      - SELL: close < SMA(trend_filter_period) — long-term downtrend

    Volume confirmation: deviation must be accompanied by above-average volume.

    Exit signal: price crosses back to VWAP.

    exit_target = VWAP (mean reversion target).
    Confidence is proportional to how far price deviates from VWAP.
"""

from __future__ import annotations

from typing import List, Optional

from app.services.trading.models import Candle, Signal
from app.services.trading.strategies.base import AbstractStrategy
from app.services.trading.indicators.sma import SMA


class VWAPStrategy(AbstractStrategy):
    """VWAP mean-reversion strategy."""

    def __init__(
        self,
        trend_filter_enabled: bool = True,
        trend_filter_period: int = 200,
        deviation_pct: float = 0.02,
        sma50_period: int = 50,
    ) -> None:
        super().__init__(name="vwap")
        self.trend_filter_enabled = trend_filter_enabled
        self.trend_filter_period = trend_filter_period
        self.deviation_pct = deviation_pct
        self.sma50_period = sma50_period

    async def analyze(self, candles: List[Candle]) -> List[Signal]:
        """Analyze candles for VWAP deviation signals."""
        signals: List[Signal] = []
        min_candles = max(
            self.trend_filter_period if self.trend_filter_enabled else 0,
            self.sma50_period + 5,
        )

        if len(candles) < min_candles:
            return signals

        # Compute running VWAP across all candles
        cumulative_pv = 0.0
        cumulative_vol = 0.0
        vwap_values: List[float] = []

        for c in candles:
            typical_price = (c.high + c.low + c.close) / 3.0
            cumulative_pv += typical_price * c.volume
            cumulative_vol += c.volume
            vwap = cumulative_pv / cumulative_vol if cumulative_vol > 0 else c.close
            vwap_values.append(vwap)

        current = candles[-1]
        prev = candles[-2]
        current_vwap = vwap_values[-1]
        prev_vwap = vwap_values[-2] if len(vwap_values) >= 2 else current_vwap

        # Long-term trend filter SMA
        tf_val: Optional[float] = None
        if self.trend_filter_enabled:
            sma_tf = SMA(period=self.trend_filter_period)
            tf_vals = sma_tf.compute(candles)
            tf_val = tf_vals[-1]
            if tf_val is not None and tf_val != tf_val:
                return signals

        # Short-term SMA(50) for direction filter
        sma50 = SMA(period=self.sma50_period)
        sma50_vals = sma50.compute(candles)
        sma50_val = sma50_vals[-1]
        if sma50_val != sma50_val:
            return signals

        # Volume confirmation
        if len(candles) >= 6:
            avg_vol = sum(c.volume for c in candles[-6:-1]) / 5.0
            volume_ok = current.volume > avg_vol
        else:
            volume_ok = True

        deviation = abs(current.close - current_vwap) / current_vwap if current_vwap > 0 else 0.0
        # Map deviation: 2% = ~0.5 confidence, 6%+ = 1.0
        confidence = min(1.0, deviation / 0.06)

        # BUY: price below VWAP (dip) in short-term uptrend
        if current.close < current_vwap * (1 - self.deviation_pct):
            if current.close <= sma50_val:  # SMA50 directional: close > SMA50 for BUY
                return signals
            # Long-term trend filter: only BUY if close > SMA
            if tf_val is not None and current.close <= tf_val:
                return signals
            if not volume_ok:
                return signals
            signals.append(
                Signal(
                    side="BUY",
                    price=current.close,
                    time=current.timestamp,
                    type="entry",
                    confidence=confidence,
                    exit_target=current_vwap,  # mean reversion to VWAP
                )
            )

        # SELL: price above VWAP (rally) in short-term downtrend
        elif current.close > current_vwap * (1 + self.deviation_pct):
            if current.close >= sma50_val:  # SMA50 directional: close < SMA50 for SELL
                return signals
            # Long-term trend filter: only SELL if close < SMA
            if tf_val is not None and current.close >= tf_val:
                return signals
            if not volume_ok:
                return signals
            signals.append(
                Signal(
                    side="SELL",
                    price=current.close,
                    time=current.timestamp,
                    type="entry",
                    confidence=confidence,
                    exit_target=current_vwap,  # mean reversion to VWAP
                )
            )

        # Exit signal: price crossed back to VWAP
        prev_below = prev.close < prev_vwap
        curr_below = current.close < current_vwap
        if prev_below != curr_below:
            if curr_below:
                signals.append(
                    Signal(
                        side="BUY",
                        price=current.close,
                        time=current.timestamp,
                        type="exit",
                        confidence=0.7,
                    )
                )
            else:
                signals.append(
                    Signal(
                        side="SELL",
                        price=current.close,
                        time=current.timestamp,
                        type="exit",
                        confidence=0.7,
                    )
                )

        return signals


# Backward compatibility alias
VWAP = VWAPStrategy
