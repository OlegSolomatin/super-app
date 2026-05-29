"""Volume Spike indicator.

Detects unusual volume activity by comparing current volume against
a rolling average.  A spike is flagged when volume exceeds the average
by a configurable multiplier threshold.
"""

from __future__ import annotations

from typing import List

from app.services.trading.indicators.base import AbstractIndicator
from app.services.trading.models import Candle


class VolumeSpike(AbstractIndicator):
    """Volume Spike detector.

    Values > 1.0 indicate a spike (volume > threshold * avg_volume).
    """

    def __init__(self, period: int = 20, threshold: float = 2.0) -> None:
        super().__init__(period=period)
        self.threshold = threshold

    def compute(self, candles: List[Candle]) -> List[float]:
        """Compute volume spike ratio (current_volume / avg_volume).

        Returns NaN during warmup.  Values >= threshold indicate a spike.
        """
        result: List[float] = []
        cumulative_volume = 0.0

        for i, c in enumerate(candles, start=1):
            cumulative_volume += c.volume
            if i < self.period:
                result.append(float("nan"))
            else:
                if i > self.period:
                    cumulative_volume -= candles[i - self.period - 1].volume
                avg_volume = cumulative_volume / self.period
                ratio = c.volume / avg_volume if avg_volume > 0 else float("nan")
                result.append(ratio)

        return result
