"""Supertrend strategy.

Logic:
    ATR-based trend-following indicator.
      - ATR(14) calculated using True Range
      - Upper band = (high + low) / 2 + multiplier * ATR
      - Lower band = (high + low) / 2 - multiplier * ATR

    BUY  when close crosses above the lower band (trend flips up).
    SELL when close crosses below the upper band (trend flips down).

    Parameters: multiplier=3, period=10.

    Confidence is based on the normalised distance between close and the
    opposite band.
"""

from __future__ import annotations

from typing import List, Optional

from app.services.trading.models import Candle, Signal
from app.services.trading.strategies.base import AbstractStrategy
from app.services.trading.indicators.sma import SMA


class SupertrendStrategy(AbstractStrategy):
    """Supertrend strategy using ATR-based bands."""

    def __init__(
        self,
        trend_filter_enabled: bool = True,
        trend_filter_period: int = 200,
        atr_period: int = 14,
        multiplier: float = 4.0,
    ) -> None:
        super().__init__(name="supertrend")
        self.trend_filter_enabled = trend_filter_enabled
        self.trend_filter_period = trend_filter_period
        self.atr_period = atr_period
        self.multiplier = multiplier

    async def analyze(self, candles: List[Candle]) -> List[Signal]:
        """Analyze candles for Supertrend signals."""
        signals: List[Signal] = []
        min_candles = max(self.trend_filter_period, self.atr_period + 5) if self.trend_filter_enabled else self.atr_period + 5

        if len(candles) < min_candles:
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

        # Compute Supertrend
        trend_direction, upper_bands, lower_bands = self._compute_supertrend(candles)

        if len(trend_direction) < 2:
            return signals

        prev_direction = trend_direction[-2]
        curr_direction = trend_direction[-1]

        if prev_direction != prev_direction or curr_direction != curr_direction:
            return signals

        # BUY: trend flipped from downtrend (-1) to uptrend (+1)
        # Require close to be 0.5% above lower band for confirmation
        if curr_direction == 1 and prev_direction == -1 and current.close > lower_bands[-1] * 1.003:
            # Directional trend filter: only BUY if close > SMA
            if tf_val is not None and current.close <= tf_val:
                return signals
            if not volume_ok:
                return signals
            confidence = self._compute_confidence(current.close, lower_bands[-1])
            signals.append(
                Signal(
                    side="BUY",
                    price=current.close,
                    time=current.timestamp,
                    type="entry",
                    confidence=confidence,
                )
            )

        # SELL: trend flipped from uptrend (+1) to downtrend (-1)
        # Require close to be 0.5% below upper band for confirmation
        elif curr_direction == -1 and prev_direction == 1 and current.close < upper_bands[-1] * 0.997:
            # Directional trend filter: only SELL if close < SMA
            if tf_val is not None and current.close >= tf_val:
                return signals
            if not volume_ok:
                return signals
            confidence = self._compute_confidence(upper_bands[-1], current.close)
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

    @staticmethod
    def _compute_confidence(value: float, reference: float) -> float:
        """Compute confidence as % distance from reference, mapped to 0-1.

        A close 0.5% from band → confidence ~0.5
        A close 1% from band → confidence ~1.0
        """
        if reference == 0:
            return 0.0
        raw = abs(value - reference) / reference
        # Scale: 0.5% distance = ~0.5 confidence; 1%+ = 1.0
        return min(1.0, raw)

    def _compute_supertrend(self, candles: List[Candle]) -> tuple[List[float], List[float], List[float]]:
        """Compute Supertrend values.

        Returns:
            Tuple of (trend_direction, upper_bands, lower_bands).
            - trend_direction: +1 for uptrend, -1 for downtrend, NaN initially
            - upper_bands and lower_bands are the band values at each step
        """
        n = len(candles)
        period = self.atr_period
        multiplier = self.multiplier

        direction: List[float] = [float("nan")] * n
        upper_band: List[float] = [float("nan")] * n
        lower_band: List[float] = [float("nan")] * n

        if n < 2:
            return direction, upper_band, lower_band

        # Step 1: True Range
        tr: List[float] = [0.0] * n
        for i in range(1, n):
            tr[i] = max(
                candles[i].high - candles[i].low,
                abs(candles[i].high - candles[i - 1].close),
                abs(candles[i].low - candles[i - 1].close),
            )
        tr[0] = candles[0].high - candles[0].low

        # Step 2: ATR using Wilder's smoothing
        atr: List[float] = [float("nan")] * n
        if n >= period:
            atr[period - 1] = sum(tr[:period]) / period
            for i in range(period, n):
                atr[i] = (atr[i - 1] * (period - 1) + tr[i]) / period

        # Step 3: Calculate bands and direction
        for i in range(1, n):
            if atr[i] != atr[i]:  # NaN
                continue

            hl2 = (candles[i].high + candles[i].low) / 2.0
            ub = hl2 + multiplier * atr[i]
            lb = hl2 - multiplier * atr[i]

            if i == 1 or direction[i - 1] != direction[i - 1]:
                # Initial: use simple comparison
                upper_band[i] = ub
                lower_band[i] = lb
                if candles[i].close <= ub:
                    direction[i] = -1.0
                else:
                    direction[i] = 1.0
            else:
                # Previous direction determines which band carries over
                if direction[i - 1] == 1.0:
                    # Uptrend: use lower band
                    lower_band[i] = max(lb, lower_band[i - 1]) if lower_band[i - 1] == lower_band[i - 1] else lb
                    upper_band[i] = ub
                    if candles[i].close < lower_band[i]:
                        direction[i] = -1.0
                    else:
                        direction[i] = 1.0
                else:
                    # Downtrend: use upper band
                    upper_band[i] = min(ub, upper_band[i - 1]) if upper_band[i - 1] == upper_band[i - 1] else ub
                    lower_band[i] = lb
                    if candles[i].close > upper_band[i]:
                        direction[i] = 1.0
                    else:
                        direction[i] = -1.0

        return direction, upper_band, lower_band


# Backward compatibility alias
Supertrend = SupertrendStrategy
