"""RSI Oversold / Overbought strategy.

Logic:
    BUY  when RSI(14) drops below oversold_threshold and stays below
         for two consecutive candles — confirmed oversold condition.
    SELL when RSI(14) climbs above overbought_threshold and stays above
         for two consecutive candles — confirmed overbought condition.

    Trend filter is directional:
      - BUY:  close > SMA(trend_filter_period) — only buy in uptrend
      - SELL: close < SMA(trend_filter_period) — only sell in downtrend

    Volume confirmation: current volume must exceed average of last 5 candles.

    Exit signals:
      - Exit BUY  when RSI recovers above rsi_exit_buy
      - Exit SELL when RSI drops below rsi_exit_sell

    Confidence is based on how extreme the RSI value is.
    exit_target is calculated dynamically by the engine (entry ± ATR×2).
"""

from __future__ import annotations

from typing import List, Optional

from app.services.trading.models import Candle, Signal
from app.services.trading.strategies.base import AbstractStrategy
from app.services.trading.indicators.rsi import RSI
from app.services.trading.indicators.sma import SMA


class RsiOversoldStrategy(AbstractStrategy):
    """RSI oversold / overbought strategy."""

    def __init__(
        self,
        trend_filter_enabled: bool = True,
        trend_filter_period: int = 200,
        rsi_period: int = 14,
        oversold_threshold: float = 25.0,
        overbought_threshold: float = 75.0,
        exit_buy_threshold: float = 60.0,
        exit_sell_threshold: float = 40.0,
    ) -> None:
        super().__init__(name="rsi_oversold")
        self.trend_filter_enabled = trend_filter_enabled
        self.trend_filter_period = trend_filter_period
        self.rsi_period = rsi_period
        self.oversold_threshold = oversold_threshold
        self.overbought_threshold = overbought_threshold
        self.exit_buy_threshold = exit_buy_threshold
        self.exit_sell_threshold = exit_sell_threshold

    async def analyze(self, candles: List[Candle]) -> List[Signal]:
        """Analyze candles for RSI oversold / overbought signals."""
        signals: List[Signal] = []
        min_candles = max(self.trend_filter_period, self.rsi_period + 5) if self.trend_filter_enabled else self.rsi_period + 5

        if len(candles) < min_candles:
            return signals

        rsi_indicator = RSI(period=self.rsi_period)
        rsi_values = rsi_indicator.compute(candles)

        if len(rsi_values) < 2:
            return signals

        rsi_prev = rsi_values[-2]
        rsi_curr = rsi_values[-1]

        # Skip if any value is NaN
        if rsi_prev != rsi_prev or rsi_curr != rsi_curr:
            return signals

        current = candles[-1]

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

        # BUY: RSI below oversold threshold with confirmation
        if rsi_curr < self.oversold_threshold and rsi_prev < self.oversold_threshold:
            # Directional trend filter: only BUY if close > SMA
            if tf_val is not None and current.close <= tf_val:
                return signals
            if not volume_ok:
                return signals
            confidence = 1.0 - rsi_curr / 100.0
            signals.append(
                Signal(
                    side="BUY",
                    price=current.close,
                    time=current.timestamp,
                    type="entry",
                    confidence=confidence,
                )
            )

        # SELL: RSI above overbought threshold with confirmation
        elif rsi_curr > self.overbought_threshold and rsi_prev > self.overbought_threshold:
            # Directional trend filter: only SELL if close < SMA
            if tf_val is not None and current.close >= tf_val:
                return signals
            if not volume_ok:
                return signals
            confidence = rsi_curr / 100.0
            signals.append(
                Signal(
                    side="SELL",
                    price=current.close,
                    time=current.timestamp,
                    type="entry",
                    confidence=confidence,
                )
            )

        # Exit BUY when RSI recovers above exit_buy_threshold
        if rsi_curr > self.exit_buy_threshold and rsi_prev <= self.exit_buy_threshold:
            signals.append(
                Signal(
                    side="SELL",
                    price=current.close,
                    time=current.timestamp,
                    type="exit",
                    confidence=0.8,
                )
            )

        # Exit SELL when RSI drops below exit_sell_threshold
        if rsi_curr < self.exit_sell_threshold and rsi_prev >= self.exit_sell_threshold:
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
RsiOversold = RsiOversoldStrategy
