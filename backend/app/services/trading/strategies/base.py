"""Abstract base class for trading strategies."""

from __future__ import annotations

from abc import ABC, abstractmethod
from typing import List

from app.services.trading.models import Candle, Signal


class AbstractStrategy(ABC):
    """Base class for all trading strategies.

    Subclasses must implement analyze() which inspects a candle or
    a window of candles and returns a list of signals.
    """

    def __init__(self, name: str = "") -> None:
        self.name = name or self.__class__.__name__

    @abstractmethod
    async def analyze(self, candles: List[Candle]) -> List[Signal]:
        """Analyze the current candle window and produce signals.

        Args:
            candles: Chronological list of OHLCV candles.

        Returns:
            A list of Signal objects (empty if no action is warranted).
        """
        ...
