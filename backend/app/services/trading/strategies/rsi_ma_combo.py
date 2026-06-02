"""RSI + MA Combo strategy.

Logic:
    Combines RSI and moving average filters for higher-conviction signals.

    BUY  when RSI(14) < 40 AND close > SMA(50)
         — oversold condition within a short-term uptrend.
    SELL when RSI(14) > 60 AND close < SMA(50)
         — overbought condition within a short-term downtrend.

    Both conditions must be true before a signal is generated.
    Uses RSI indicator from app.services.trading.indicators.rsi
    Uses SMA indicator from app.services.trading.indicators.sma
"""

from __future__ import annotations

from typing import List, Optional

from app.services.trading.models import Candle, Signal
from app.services.trading.strategies.base import AbstractStrategy
from app.services.trading.indicators.rsi import RSI
from app.services.trading.indicators.sma import SMA


class RSIMACombo(AbstractStrategy):
    """RSI + Moving Average combo strategy."""

    def __init__(
        self,
        trend_filter_enabled: bool = True,
        trend_filter_period: int = 200,
    ) -> None:
        super().__init__(name="rsi_ma_combo")
        self.trend_filter_enabled = trend_filter_enabled
        self.trend_filter_period = trend_filter_period

    async def analyze(self, candles: List[Candle]) -> List[Signal]:
        """Analyze candles for RSI + MA combo signals."""
        signals: List[Signal] = []
        rsi_period = 14
        sma_period = 20
        min_candles = max(sma_period, rsi_period) + 1

        if len(candles) < min_candles:
            return signals

        # Compute RSI(14)
        rsi_indicator = RSI(period=rsi_period)
        rsi_values = rsi_indicator.compute(candles)
        current_rsi = rsi_values[-1]

        # Compute SMA(50) — this serves as the trend filter
        sma_indicator = SMA(period=sma_period)
        sma_values = sma_indicator.compute(candles)
        current_sma = sma_values[-1]

        # Skip if any value is NaN
        if current_rsi != current_rsi or current_sma != current_sma:
            return signals

        current = candles[-1]

        # BUY: RSI < 45 AND close > SMA(20) — oversold in short-term uptrend
        if current_rsi < 45 and current.close > current_sma:
            # Confidence based on RSI distance below 45
            rsi_factor = (45.0 - current_rsi) / 45.0
            confidence = min(1.0, 0.5 + rsi_factor)
            signals.append(
                Signal(
                    side="BUY",
                    price=current.close,
                    time=current.timestamp,
                    type="entry",
                    confidence=confidence,
                )
            )

        # SELL: RSI > 55 AND close < SMA(20) — overbought in short-term downtrend
        elif current_rsi > 55 and current.close < current_sma:
            rsi_factor = (current_rsi - 55.0) / 40.0
            confidence = min(1.0, 0.5 + rsi_factor)
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
RSIMAComboStrategy = RSIMACombo
