"""Binance exchange connector (stub)."""

from __future__ import annotations

from datetime import datetime
from typing import Dict, List, Optional

from app.services.trading.exchange.base import AbstractExchange
from app.services.trading.models import Candle


class BinanceExchange(AbstractExchange):
    """Binance exchange connector.

    API docs: https://binance-docs.github.io/apidocs/spot/en/
    """

    def __init__(self, api_key: str = "", api_secret: str = "") -> None:
        super().__init__(name="binance", api_key=api_key, api_secret=api_secret)

    async def get_klines(
        self,
        pair: str,
        timeframe: str,
        start: Optional[datetime] = None,
        end: Optional[datetime] = None,
        limit: int = 500,
    ) -> List[Candle]:
        """Fetch historical klines from Binance."""
        # TODO: implement Binance API GET /api/v3/klines
        return []

    async def get_ticker(self, pair: str) -> Dict[str, float]:
        """Fetch current ticker from Binance."""
        # TODO: implement Binance API GET /api/v3/ticker/24hr
        return {}

    async def place_order(
        self,
        pair: str,
        side: str,
        quantity: float,
        order_type: str = "market",
        price: Optional[float] = None,
    ) -> Dict:
        """Place order on Binance."""
        # TODO: implement Binance API POST /api/v3/order
        return {}

    async def get_balance(self, currency: str = "") -> Dict[str, float]:
        """Fetch account balance from Binance."""
        # TODO: implement Binance API GET /api/v3/account
        return {}
