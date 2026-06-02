"""ADX (Average Directional Index) strategy.

Logic:
    ADX measures trend strength (non-directional).
    +DI and -DI measure directional movement:
      - BUY:  ADX > 25  AND  +DI > -DI
      - SELL: ADX > 25  AND  -DI > +DI

    All calculations are done inline (True Range, directional movement,
    smoothed +DI/-DI, ADX).

    Confidence is based on ADX value scaled to [0, 1] (ADX / 100).
"""

from __future__ import annotations

from typing import List, Optional

from app.services.trading.models import Candle, Signal
from app.services.trading.strategies.base import AbstractStrategy
from app.services.trading.indicators.sma import SMA


class AdxStrategy(AbstractStrategy):
    """ADX (Average Directional Index) strategy."""

    def __init__(
        self,
        trend_filter_enabled: bool = True,
        trend_filter_period: int = 200,
        adx_period: int = 14,
    ) -> None:
        super().__init__(name="adx")
        self.trend_filter_enabled = trend_filter_enabled
        self.trend_filter_period = trend_filter_period
        self.adx_period = adx_period

    async def analyze(self, candles: List[Candle]) -> List[Signal]:
        """Analyze candles for ADX-based directional signals."""
        signals: List[Signal] = []
        # Need at least 2 * adx_period candles for a meaningful ADX
        min_candles = max(
            self.trend_filter_period if self.trend_filter_enabled else 0,
            2 * self.adx_period + 10,
        )

        if len(candles) < min_candles:
            return signals

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

        # Compute ADX, +DI, -DI
        adx_values, plus_di, minus_di = self._compute_adx(candles)

        if len(adx_values) < 2:
            return signals

        adx_curr = adx_values[-1]
        plus_di_curr = plus_di[-1]
        minus_di_curr = minus_di[-1]
        plus_di_prev = plus_di[-2] if len(plus_di) >= 2 else float('nan')
        minus_di_prev = minus_di[-2] if len(minus_di) >= 2 else float('nan')

        # Skip if any value is NaN
        if any(v != v for v in (adx_curr, plus_di_curr, minus_di_curr, plus_di_prev, minus_di_prev)):
            return signals

        confidence = min(1.0, adx_curr / 100.0)

        # BUY: strong trend (ADX > 30) AND +DI > -DI AND +DI was > -DI previously
        if adx_curr > 30 and plus_di_curr > minus_di_curr and plus_di_prev > minus_di_prev:
            signals.append(
                Signal(
                    side="BUY",
                    price=current.close,
                    time=current.timestamp,
                    type="entry",
                    confidence=confidence,
                )
            )

        # SELL: strong trend (ADX > 30) AND -DI > +DI AND -DI was > +DI previously
        elif adx_curr > 30 and minus_di_curr > plus_di_curr and minus_di_prev > plus_di_prev:
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

    def _compute_adx(self, candles: List[Candle]) -> tuple[List[float], List[float], List[float]]:
        """Compute ADX, +DI, and -DI values.

        Returns:
            Tuple of (adx_values, plus_di_values, minus_di_values).
            Each list has the same length as candles, with NaN for leading
            positions where there isn't enough data.
        """
        n = len(candles)
        adx: List[float] = [float("nan")] * n
        pdi: List[float] = [float("nan")] * n
        ndi: List[float] = [float("nan")] * n

        if n < 2:
            return adx, pdi, ndi

        # Step 1: True Range (TR), +DM, -DM
        tr_values: List[float] = [float("nan")] * n
        plus_dm: List[float] = [float("nan")] * n
        minus_dm: List[float] = [float("nan")] * n

        for i in range(1, n):
            high = candles[i].high
            low = candles[i].low
            prev_close = candles[i - 1].close

            # True Range
            tr = max(
                high - low,
                abs(high - prev_close),
                abs(low - prev_close),
            )
            tr_values[i] = tr

            # Directional Movement
            up_move = high - candles[i - 1].high
            down_move = candles[i - 1].low - low

            if up_move > down_move and up_move > 0:
                plus_dm[i] = up_move
            else:
                plus_dm[i] = 0.0

            if down_move > up_move and down_move > 0:
                minus_dm[i] = down_move
            else:
                minus_dm[i] = 0.0

        # Step 2: Wilder's smoothing (first SMA, then EMA-like)
        # Smoothed TR
        smoothed_tr: List[float] = [float("nan")] * n
        smoothed_plus_dm: List[float] = [float("nan")] * n
        smoothed_minus_dm: List[float] = [float("nan")] * n

        # First smoothed value = simple average of first `period` values
        period = self.adx_period
        if n < period + 1:
            return adx, pdi, ndi

        # Initial SMA
        tr_sum = sum(tr_values[1 : period + 1])
        pdm_sum = sum(plus_dm[1 : period + 1])
        mdm_sum = sum(minus_dm[1 : period + 1])

        smoothed_tr[period] = tr_sum
        smoothed_plus_dm[period] = pdm_sum
        smoothed_minus_dm[period] = mdm_sum

        for i in range(period + 1, n):
            smoothed_tr[i] = smoothed_tr[i - 1] - (smoothed_tr[i - 1] / period) + tr_values[i]
            smoothed_plus_dm[i] = smoothed_plus_dm[i - 1] - (smoothed_plus_dm[i - 1] / period) + plus_dm[i]
            smoothed_minus_dm[i] = smoothed_minus_dm[i - 1] - (smoothed_minus_dm[i - 1] / period) + minus_dm[i]

        # Step 3: +DI and -DI
        for i in range(period, n):
            if smoothed_tr[i] != 0:
                pdi[i] = 100.0 * smoothed_plus_dm[i] / smoothed_tr[i]
                ndi[i] = 100.0 * smoothed_minus_dm[i] / smoothed_tr[i]
            else:
                pdi[i] = 0.0
                ndi[i] = 0.0

        # Step 4: DX and ADX
        dx_values: List[float] = [float("nan")] * n
        for i in range(period, n):
            di_sum = pdi[i] + ndi[i]
            di_diff = abs(pdi[i] - ndi[i])
            if di_sum != 0:
                dx_values[i] = 100.0 * di_diff / di_sum
            else:
                dx_values[i] = 0.0

        # First ADX = SMA of DX
        dx_sum = sum(dx_values[period : period + period])
        adx[period + period - 1] = dx_sum / period

        for i in range(period + period, n):
            adx[i] = (adx[i - 1] * (period - 1) + dx_values[i]) / period

        return adx, pdi, ndi


# Backward compatibility alias
ADX = AdxStrategy
