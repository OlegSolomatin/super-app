"""RSI + MA Combo strategy.

Logic:
    Combines RSI and two moving average filters for higher-conviction signals.

    BUY  when RSI(buy_rsi_period) < buy_rsi_threshold AND close > SMA(signal_sma_period)
         AND close > SMA(trend_filter_period) — oversold in long-term uptrend.
    SELL when RSI(sell_rsi_period) > sell_rsi_threshold AND close < SMA(signal_sma_period)
         AND close < SMA(trend_filter_period) — overbought in long-term downtrend.

    Volume confirmation: current volume must exceed average of last 5 candles.

    Exit signal: RSI crosses back to neutral (50).

    Confidence is based on RSI distance from thresholds.
    exit_target is calculated dynamically by the engine (entry ± ATR×2).
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
        rsi_period: int = 14,
        signal_sma_period: int = 20,
        buy_rsi_threshold: float = 45.0,
        sell_rsi_threshold: float = 55.0,
    ) -> None:
        super().__init__(name="rsi_ma_combo")
        self.trend_filter_enabled = trend_filter_enabled
        self.trend_filter_period = trend_filter_period
        self.rsi_period = rsi_period
        self.signal_sma_period = signal_sma_period
        self.buy_rsi_threshold = buy_rsi_threshold
        self.sell_rsi_threshold = sell_rsi_threshold

    async def analyze(self, candles: List[Candle]) -> List[Signal]:
        """Analyze candles for RSI + MA combo signals."""
        signals: List[Signal] = []
        min_candles = max(
            self.trend_filter_period if self.trend_filter_enabled else 0,
            self.signal_sma_period + self.rsi_period + 5,
        )

        if len(candles) < min_candles:
            return signals

        # Compute RSI
        rsi_indicator = RSI(period=self.rsi_period)
        rsi_values = rsi_indicator.compute(candles)
        current_rsi = rsi_values[-1]
        prev_rsi = rsi_values[-2] if len(rsi_values) >= 2 else float('nan')

        # Compute signal SMA
        sma_indicator = SMA(period=self.signal_sma_period)
        sma_values = sma_indicator.compute(candles)
        current_sma = sma_values[-1]

        # Skip if any value is NaN
        if current_rsi != current_rsi or prev_rsi != prev_rsi or current_sma != current_sma:
            return signals

        current = candles[-1]

        # Long-term trend filter SMA
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

        # BUY: RSI < threshold AND close > signal SMA AND close > long-term SMA
        if current_rsi < self.buy_rsi_threshold and current.close > current_sma:
            if tf_val is not None and current.close <= tf_val:
                return signals
            if not volume_ok:
                return signals
            rsi_factor = (self.buy_rsi_threshold - current_rsi) / self.buy_rsi_threshold
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

        # SELL: RSI > threshold AND close < signal SMA AND close < long-term SMA
        elif current_rsi > self.sell_rsi_threshold and current.close < current_sma:
            if tf_val is not None and current.close >= tf_val:
                return signals
            if not volume_ok:
                return signals
            rsi_factor = (current_rsi - self.sell_rsi_threshold) / (100.0 - self.sell_rsi_threshold)
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

        # Exit signal: RSI crosses back to neutral (50 from either side)
        if prev_rsi <= 50 and current_rsi > 50:
            signals.append(
                Signal(
                    side="SELL",
                    price=current.close,
                    time=current.timestamp,
                    type="exit",
                    confidence=0.8,
                )
            )
        elif prev_rsi >= 50 and current_rsi < 50:
            signals.append(
                Signal(
                    side="BUY",
                    price=current.close,
                    time=current.timestamp,
                    type="exit",
                    confidence=0.8,
                )
            )

        return signals


# Backward compatibility alias
RSIMAComboStrategy = RSIMACombo
