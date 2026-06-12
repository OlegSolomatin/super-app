"""
Stair Climber (🪜 Лесенка) — ступенчатый рост/падение цены с нарастающим объёмом.

Logic:
    Find N consecutive candles (N=3-5) forming a staircase:
      - BUY:  higher highs + higher lows + growing volume (×1.2+ each step)
      - SELL: lower highs + lower lows + growing volume (×1.2+ each step)

    Slope = (price_N - price_0) / N / ATR(14)
    - slope >= slope_threshold → trend confirmed

    Entry on pullback: price near EMA(pullback_ema) after the streak.
    Exit: TP = next step level, SL = previous step level.
    Confidence proportional to slope strength.

    1m–3m timeframe recommended (short-term pattern).
"""

from __future__ import annotations

from typing import List, Optional, Tuple

from app.services.trading.models import Candle, Signal
from app.services.trading.strategies.base import AbstractStrategy
from app.services.trading.indicators.ema import EMA
from app.services.trading.indicators.sma import SMA

# Maximum candles to scan backwards for a staircase pattern
MAX_LOOKBACK = 10
# ATR period for slope normalisation
ATR_PERIOD = 14
# Max distance from EMA (in ATR units) for pullback entry
PULLBACK_MAX_ATR = 0.5


class StairClimberStrategy(AbstractStrategy):
    """Stair climber — finds step-like price movements with volume confirmation."""

    def __init__(
        self,
        min_steps: int = 3,
        slope_threshold: float = 3.0,
        volume_growth: float = 1.2,
        pullback_ema: int = 9,
        trend_filter_enabled: bool = True,
        trend_filter_period: int = 200,
    ) -> None:
        super().__init__(name="stair_climber")
        self.min_steps = min_steps
        self.slope_threshold = slope_threshold
        self.volume_growth = volume_growth
        self.pullback_ema = pullback_ema
        self.trend_filter_enabled = trend_filter_enabled
        self.trend_filter_period = trend_filter_period

    # ──────────────────────────────────────────────
    # ATR computation
    # ──────────────────────────────────────────────

    @staticmethod
    def _compute_atr(candles: List[Candle], period: int = ATR_PERIOD) -> List[float]:
        """Compute Average True Range (SMA of true range)."""
        tr_values: List[float] = []
        for i, c in enumerate(candles):
            if i == 0:
                tr = c.high - c.low
            else:
                tr = max(
                    c.high - c.low,
                    abs(c.high - candles[i - 1].close),
                    abs(c.low - candles[i - 1].close),
                )
            tr_values.append(tr)

        atr: List[float] = []
        for i in range(len(candles)):
            if i + 1 < period:
                atr.append(float("nan"))
            elif i + 1 == period:
                atr.append(sum(tr_values[:period]) / period)
            else:
                atr.append((atr[-1] * (period - 1) + tr_values[i]) / period)
        return atr

    # ──────────────────────────────────────────────
    # Staircase detection
    # ──────────────────────────────────────────────

    def _detect_staircase(
        self,
        candles: List[Candle],
        start_idx: int,
    ) -> Tuple[bool, bool, int, float, float, float]:
        """Detect a staircase pattern starting at start_idx.

        Returns (is_ascending, is_descending, streak_len, slope, volume_ratio, avg_atr).
        """
        is_ascending = True
        is_descending = True
        streak_len = 0

        for j in range(start_idx + 1, min(start_idx + 5 + 1, len(candles))):
            prev = candles[j - 1]
            curr = candles[j]

            if curr.high <= prev.high or curr.low <= prev.low:
                is_ascending = False
            if curr.high >= prev.high or curr.low >= prev.low:
                is_descending = False

            if not is_ascending and not is_descending:
                break
            streak_len += 1

        if streak_len < self.min_steps:
            return False, False, 0, 0.0, 0.0, 0.0

        # Volume growth check
        vol_ok = True
        for j in range(start_idx + 1, start_idx + streak_len + 1):
            if candles[j].volume < candles[j - 1].volume * self.volume_growth:
                vol_ok = False
                break

        if not vol_ok:
            return False, False, 0, 0.0, 0.0, 0.0

        # Calculate slope
        start_c = candles[start_idx]
        end_c = candles[start_idx + streak_len]

        atr_vals = self._compute_atr(candles)
        avg_atr = atr_vals[start_idx + streak_len]
        if avg_atr != avg_atr or avg_atr <= 0:
            return False, False, 0, 0.0, 0.0, 0.0

        if is_ascending:
            price_change = end_c.high - start_c.low
        elif is_descending:
            price_change = start_c.high - end_c.low
        else:
            return False, False, 0, 0.0, 0.0, 0.0

        slope = abs(price_change) / streak_len / avg_atr

        return is_ascending, is_descending, streak_len, slope, vol_ok, avg_atr

    # ──────────────────────────────────────────────
    # Main analysis
    # ──────────────────────────────────────────────

    async def analyze(self, candles: List[Candle]) -> List[Signal]:
        """Analyze candles for staircase patterns with pullback entry."""
        signals: List[Signal] = []

        min_candles = max(
            self.pullback_ema + 5,
            self.trend_filter_period if self.trend_filter_enabled else 0,
            ATR_PERIOD + MAX_LOOKBACK,
        )
        if len(candles) < min_candles:
            return signals

        current = candles[-1]

        # ── EMA(pullback_ema) ──
        ema = EMA(period=self.pullback_ema)
        ema_vals = ema.compute(candles)
        current_ema = ema_vals[-1]
        if current_ema != current_ema:
            return signals

        # ── ATR ──
        atr_vals = self._compute_atr(candles)
        current_atr = atr_vals[-1]
        if current_atr != current_atr or current_atr <= 0:
            return signals

        # ── Pullback proximity check ──
        pullback_dist = abs(current.close - current_ema) / current_atr
        if pullback_dist > PULLBACK_MAX_ATR:
            # Price is not near EMA — no pullback entry
            return signals

        # ── Trend filter (SMA) ──
        tf_val: Optional[float] = None
        if self.trend_filter_enabled:
            sma_tf = SMA(period=self.trend_filter_period)
            tf_vals = sma_tf.compute(candles)
            tf_val = tf_vals[-1]
            if tf_val is None or tf_val != tf_val:
                return signals

        # ── Scan backwards for staircase patterns ──
        best_slope = 0.0
        best_streak = 0
        best_is_ascending = False
        best_start_idx = -1

        scan_start = max(ATR_PERIOD, len(candles) - MAX_LOOKBACK)
        for start_idx in range(scan_start, len(candles) - self.min_steps):
            asc, desc, streak_len, slope, _vol_ok, _avg_atr = self._detect_staircase(
                candles, start_idx
            )
            if streak_len < self.min_steps or slope < self.slope_threshold:
                continue
            if slope > best_slope:
                best_slope = slope
                best_streak = streak_len
                best_is_ascending = asc  # asc or desc
                best_start_idx = start_idx

        if best_start_idx < 0:
            return signals

        # ── Direction filter ──
        start_c = candles[best_start_idx]
        end_c = candles[best_start_idx + best_streak]

        if best_is_ascending:
            # BUY: staircase going up, price pulled back to EMA
            if tf_val is not None and current.close <= tf_val:
                return signals
            if current.close >= end_c.high:
                # Already above the staircase — too late
                return signals

            # Entry on pullback to EMA
            if current.close < current_ema * 0.995:
                # Too far below EMA — not a pullback, may be a reversal
                return signals

            # Exit targets
            tp_price = end_c.high
            sl_price = start_c.low
            conf = min(1.0, best_slope / 8.0)
            # Add streak bonus
            conf = min(1.0, conf + (best_streak - self.min_steps) * 0.1)

            signals.append(
                Signal(
                    side="BUY",
                    price=current.close,
                    time=current.timestamp,
                    type="entry",
                    confidence=conf,
                    exit_target=tp_price,
                )
            )

        else:
            # SELL: staircase going down, price pulled back to EMA
            if tf_val is not None and current.close >= tf_val:
                return signals
            if current.close <= end_c.low:
                return signals

            if current.close > current_ema * 1.005:
                return signals

            tp_price = end_c.low
            sl_price = start_c.high
            conf = min(1.0, best_slope / 8.0)
            conf = min(1.0, conf + (best_streak - self.min_steps) * 0.1)

            signals.append(
                Signal(
                    side="SELL",
                    price=current.close,
                    time=current.timestamp,
                    type="entry",
                    confidence=conf,
                    exit_target=tp_price,
                )
            )

        return signals
