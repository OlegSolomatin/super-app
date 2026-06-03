"""On-Balance Volume (OBV) divergence strategy.

Logic:
    OBV = cumulative volume adjusted by price direction:
      - If close > prev_close: OBV += volume
      - If close < prev_close: OBV -= volume
      - If close == prev_close: OBV unchanged

    BUY  (positive divergence): OBV rising over last N periods
         while price is falling over last N periods (accumulation).
    SELL (negative divergence): OBV falling over last N periods
         while price is rising over last N periods (distribution).

    Trend filter is directional:
      - BUY:  close > SMA(trend_filter_period)
      - SELL: close < SMA(trend_filter_period)

    Two-candle confirmation: divergence must persist for 2+ consecutive candles.

    Confidence is based on OBV trend strength normalised by average volume.
    exit_target is calculated dynamically by the engine (entry ± ATR×2).
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
        lookback: int = 5,
    ) -> None:
        super().__init__(name="obv")
        self.trend_filter_enabled = trend_filter_enabled
        self.trend_filter_period = trend_filter_period
        self.lookback = lookback

    async def analyze(self, candles: List[Candle]) -> List[Signal]:
        """Analyze candles for OBV divergence signals."""
        signals: List[Signal] = []
        min_candles = max(self.trend_filter_period, self.lookback + 5) if self.trend_filter_enabled else self.lookback + 5

        if len(candles) < min_candles:
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
        prev = candles[-2]

        # Trend filter SMA
        tf_val: Optional[float] = None
        if self.trend_filter_enabled:
            sma_tf = SMA(period=self.trend_filter_period)
            tf_vals = sma_tf.compute(candles)
            tf_val = tf_vals[-1]
            if tf_val is not None and tf_val != tf_val:
                return signals

        # Average volume for normalisation
        if len(candles) >= self.lookback + 1:
            avg_vol = sum(c.volume for c in candles[-(self.lookback + 1):]) / (self.lookback + 1)
        else:
            avg_vol = 1.0

        # Compare OBV trend vs price trend over the last `lookback` periods
        if len(candles) < self.lookback + 2:
            return signals

        obv_start = obv_values[-(self.lookback + 1)]
        obv_end = obv_values[-1]
        obv_trend = obv_end - obv_start  # positive = rising OBV

        price_start = candles[-(self.lookback + 1)].close
        price_end = candles[-1].close
        price_trend = price_end - price_start  # positive = rising price

        # Two-candle confirmation: check if divergence was also true on prev candle
        obv_prev_start = obv_values[-(self.lookback + 2)] if len(obv_values) >= self.lookback + 2 else obv_start
        obv_prev_end = obv_values[-2]
        obv_prev_trend = obv_prev_end - obv_prev_start

        price_prev_start = candles[-(self.lookback + 2)].close if len(candles) >= self.lookback + 2 else price_start
        price_prev_end = candles[-2].close
        price_prev_trend = price_prev_end - price_prev_start

        # Confidence: normalise OBV trend by average volume
        # OBV trend of 2x avg_vol over lookback = strong
        normalised_obv = abs(obv_trend) / (avg_vol * self.lookback) if avg_vol > 0 else 0.0
        confidence = min(1.0, normalised_obv)

        # BUY: positive divergence (OBV rising, price falling)
        if obv_trend > 0 and price_trend < 0:
            # Directional trend filter: only BUY if close > SMA
            if tf_val is not None and current.close <= tf_val:
                return signals
            # Two-candle confirmation: same divergence was present on previous candle
            if not (obv_prev_trend > 0 and price_prev_trend < 0):
                return signals
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
            # Directional trend filter: only SELL if close < SMA
            if tf_val is not None and current.close >= tf_val:
                return signals
            # Two-candle confirmation
            if not (obv_prev_trend < 0 and price_prev_trend > 0):
                return signals
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
