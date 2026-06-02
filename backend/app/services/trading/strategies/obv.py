"""On-Balance Volume (OBV) divergence strategy.

Logic:
    OBV = cumulative volume adjusted by price direction:
      - If close > prev_close: OBV += volume
      - If close < prev_close: OBV -= volume
      - If close == prev_close: OBV unchanged

    BUY  (positive divergence): OBV rising over last 5 periods
         while price is falling over last 5 periods (accumulation).
    SELL (negative divergence): OBV falling over last 5 periods
         while price is rising over last 5 periods (distribution).

    Compares OBV trend (last 5 periods) vs price trend (last 5 periods).
"""

from __future__ import annotations

from typing import List, Optional

from app.services.trading.models import Candle, Signal
from app.services.trading.strategies.base import AbstractStrategy
from app.services.trading.indicators.sma import SMA


class OBVStrategy(AbstractStrategy):
    """On-Balance Volume divergence strategy."""

    def __init__(
        self,
        trend_filter_enabled: bool = True,
        trend_filter_period: int = 200,
    ) -> None:
        super().__init__(name="obv")
        self.trend_filter_enabled = trend_filter_enabled
        self.trend_filter_period = trend_filter_period

    async def analyze(self, candles: List[Candle]) -> List[Signal]:
        """Analyze candles for OBV divergence signals."""
        signals: List[Signal] = []
        lookback = 5

        if len(candles) < lookback + 1:
            return signals

        # Compute OBV inline
        obv_values: List[float] = []
        obv = 0.0
        for i in range(len(candles)):
            if i == 0:
                obv = 0.0
            else:
                if candles[i].close > candles[i - 1].close:
                    obv += candles[i].volume
                elif candles[i].close < candles[i - 1].close:
                    obv -= candles[i].volume
                # else: unchanged
            obv_values.append(obv)

        current = candles[-1]

        # Trend filter: only BUY if price is above long-term SMA
        if self.trend_filter_enabled:
            sma_tf = SMA(period=self.trend_filter_period)
            tf_vals = sma_tf.compute(candles)
            tf_val = tf_vals[-1]
            if tf_val != tf_val:
                return signals
            if current.close <= tf_val:
                return signals

        # Compare OBV trend vs price trend over the last `lookback` periods
        # Need at least lookback + 1 candles for meaningful trend comparison
        if len(candles) < lookback + 1:
            return signals

        obv_start = obv_values[-(lookback + 1)]
        obv_end = obv_values[-1]
        obv_trend = obv_end - obv_start  # positive = rising OBV

        price_start = candles[-(lookback + 1)].close
        price_end = candles[-1].close
        price_trend = price_end - price_start  # positive = rising price

        # BUY: positive divergence (OBV rising, price falling)
        if obv_trend > 0 and price_trend < 0:
            # Positive divergence: OBV rising, price falling (accumulation)
            strength = abs(obv_trend) / (abs(price_trend) + 1.0)
            confidence = min(1.0, 0.5 + strength / 100000)
            signals.append(
                Signal(
                    side="BUY",
                    price=current.close,
                    time=current.timestamp,
                    type="entry",
                    confidence=confidence,
                )
            )
        # SELL: negative divergence (OBV falling, price rising)
        elif obv_trend < 0 and price_trend > 0:
            # Negative divergence: OBV falling, price rising (distribution)
            strength = abs(obv_trend) / (abs(price_trend) + 1.0)
            confidence = min(1.0, 0.5 + strength / 100000)
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
OBV = OBVStrategy
