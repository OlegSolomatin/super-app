"""Doji Detection strategy.

Logic:
    A doji is a candle where the body (|open - close|) is less than `doji_threshold`
    of the total range (high - low), indicating indecision.

    BUY:  doji formed after `min_prior`+ consecutive bearish candles (close < open)
          — potential reversal to the upside.
    SELL: doji formed after `min_prior`+ consecutive bullish candles (close > open)
          — potential reversal to the downside.

    Trend filter is directional:
      - BUY:  close > SMA(trend_filter_period) — only buy in uptrend
      - SELL: close < SMA(trend_filter_period) — only sell in downtrend

    Volume: doji on lower-than-average volume is more significant (indecision).

    exit_target = candle_range (high - low) as in Hammer strategy.
    Confidence scales with the number of preceding consecutive candles.
"""

from __future__ import annotations

from typing import List, Optional

from app.services.trading.models import Candle, Signal
from app.services.trading.strategies.base import AbstractStrategy
from app.services.trading.indicators.sma import SMA


class DojiStrategy(AbstractStrategy):
    """Doji reversal detection strategy."""

    def __init__(
        self,
        trend_filter_enabled: bool = True,
        trend_filter_period: int = 200,
        doji_threshold: float = 0.03,
        min_prior: int = 2,
    ) -> None:
        super().__init__(name="doji")
        self.trend_filter_enabled = trend_filter_enabled
        self.trend_filter_period = trend_filter_period
        self.doji_threshold = doji_threshold
        self.min_prior = min_prior

    async def analyze(self, candles: List[Candle]) -> List[Signal]:
        """Analyze candles for doji reversal patterns."""
        signals: List[Signal] = []
        min_candles = max(self.trend_filter_period, 3) if self.trend_filter_enabled else 3

        if len(candles) < min_candles:
            return signals

        current = candles[-1]

        # Determine if current candle is a doji
        body = abs(current.close - current.open)
        total_range = current.high - current.low
        is_doji = total_range > 0 and (body / total_range) < self.doji_threshold

        if not is_doji:
            return signals

        # Count consecutive bearish candles before current
        bearish_count = 0
        for c in reversed(candles[:-1]):
            if c.close < c.open:
                bearish_count += 1
            else:
                break

        # Count consecutive bullish candles before current
        bullish_count = 0
        for c in reversed(candles[:-1]):
            if c.close > c.open:
                bullish_count += 1
            else:
                break

        # Trend filter SMA
        tf_val: Optional[float] = None
        if self.trend_filter_enabled:
            sma_tf = SMA(period=self.trend_filter_period)
            tf_vals = sma_tf.compute(candles)
            tf_val = tf_vals[-1]
            if tf_val is not None and tf_val != tf_val:
                return signals

        # Volume: doji on lower volume = more significant indecision
        if len(candles) >= 6:
            avg_vol = sum(c.volume for c in candles[-6:-1]) / 5.0
            volume_ok = current.volume <= avg_vol  # doji should be on lower volume
        else:
            volume_ok = True

        candle_range = current.high - current.low

        # BUY: doji after min_prior+ bearish candles (potential reversal up)
        if bearish_count >= self.min_prior:
            # Directional trend filter: only BUY if close > SMA
            if tf_val is not None and current.close <= tf_val:
                return signals
            if not volume_ok:
                return signals
            confidence = min(1.0, 0.5 + (bearish_count - self.min_prior) * 0.15)
            signals.append(
                Signal(
                    side="BUY",
                    price=current.close,
                    time=current.timestamp,
                    type="entry",
                    confidence=confidence,
                    exit_target=current.close + candle_range,
                )
            )

        # SELL: doji after min_prior+ bullish candles (potential reversal down)
        elif bullish_count >= self.min_prior:
            # Directional trend filter: only SELL if close < SMA
            if tf_val is not None and current.close >= tf_val:
                return signals
            if not volume_ok:
                return signals
            confidence = min(1.0, 0.5 + (bullish_count - self.min_prior) * 0.15)
            signals.append(
                Signal(
                    side="SELL",
                    price=current.close,
                    time=current.timestamp,
                    type="entry",
                    confidence=confidence,
                    exit_target=current.close - candle_range,
                )
            )

        return signals


# Backward compatibility alias
Doji = DojiStrategy
