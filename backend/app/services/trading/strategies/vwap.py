"""VWAP (Volume Weighted Average Price) strategy.

Logic:
    VWAP = sum(price * volume) / sum(volume) for the session.
    Computed as a running cumulative over all candles.

    BUY  when close < VWAP * 0.98 (price 2% below VWAP = oversold intraday).
    SELL when close > VWAP * 1.02 (price 2% above VWAP = overbought intraday).

    Confidence is proportional to how far price is from VWAP.
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
    ) -> None:
        super().__init__(name="vwap")
        self.trend_filter_enabled = trend_filter_enabled
        self.trend_filter_period = trend_filter_period

    async def analyze(self, candles: List[Candle]) -> List[Signal]:
        """Analyze candles for VWAP deviation signals."""
        signals: List[Signal] = []

        if len(candles) < 2:
            return signals

        # Compute running VWAP across all candles
        cumulative_pv = 0.0
        cumulative_vol = 0.0
        vwap_values: List[float] = []

        for c in candles:
            # Typical price = (high + low + close) / 3
            typical_price = (c.high + c.low + c.close) / 3.0
            cumulative_pv += typical_price * c.volume
            cumulative_vol += c.volume
            vwap = cumulative_pv / cumulative_vol if cumulative_vol > 0 else c.close
            vwap_values.append(vwap)

        current = candles[-1]
        current_vwap = vwap_values[-1]

        # BUY: price 2% or more below VWAP AND close > SMA50 (dip in uptrend)
        if current.close < current_vwap * 0.98:
            # Check uptrend via SMA(50)
            sma50 = SMA(period=50)
            sma50_vals = sma50.compute(candles)
            sma50_val = sma50_vals[-1]
            if sma50_val == sma50_val and current.close > sma50_val:
                deviation = (current_vwap - current.close) / current_vwap if current_vwap > 0 else 0.0
                # Map deviation: 2% = ~0.5 confidence, 6%+ = 1.0
                confidence = min(1.0, deviation / 0.06)
                signals.append(
                    Signal(
                        side="BUY",
                        price=current.close,
                        time=current.timestamp,
                        type="entry",
                        confidence=confidence,
                    )
                )

        # SELL: price 2% or more above VWAP (sell the rally)
        elif current.close > current_vwap * 1.02:
            deviation = (current.close - current_vwap) / current_vwap if current_vwap > 0 else 0.0
            confidence = min(1.0, deviation / 0.06)
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
VWAP = VWAPStrategy
