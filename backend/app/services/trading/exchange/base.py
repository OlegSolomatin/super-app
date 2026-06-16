"""Abstract base class for exchange connectors.

Defines the interface all exchange implementations must adhere to.
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from datetime import datetime
from typing import Dict, List, Optional

from app.services.trading.models import Candle


class AbstractExchange(ABC):
    """Base class for cryptocurrency exchange connectors."""

    def __init__(self, name: str, api_key: str = "", api_secret: str = "") -> None:
        self.name = name
        self.api_key = api_key
        self.api_secret = api_secret

    @abstractmethod
    async def get_klines(
        self,
        pair: str,
        timeframe: str,
        start: Optional[datetime] = None,
        end: Optional[datetime] = None,
        limit: int = 500,
    ) -> List[Candle]:
        """Fetch historical OHLCV klines (candles) from the exchange."""
        ...

    @abstractmethod
    async def get_ticker(self, pair: str) -> Dict[str, float]:
        """Fetch current ticker (last price, volume, etc.) for a pair."""
        ...

    @abstractmethod
    async def place_order(
        self,
        pair: str,
        side: str,
        quantity: float,
        order_type: str = "market",
        price: Optional[float] = None,
    ) -> Dict:
        """Place an order on the exchange."""
        ...

    @abstractmethod
    async def get_balance(self, currency: str = "") -> Dict[str, float]:
        """Fetch account balance for one or all currencies."""
        ...

    @abstractmethod
    async def get_orderbook(
        self,
        pair: str,
        limit: int = 20,
    ) -> Dict:
        """Fetch current order book (bids/asks) from the exchange.

        Returns dict with:
          - bids: list of [price, quantity] sorted DESC (best first)
          - asks: list of [price, quantity] sorted ASC (best first)
          - timestamp: int (ms)
        """
        ...

    async def close(self) -> None:
        """Close any open connections. Override in subclass if needed."""
        ...
