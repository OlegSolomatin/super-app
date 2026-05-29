"""Bybit exchange connector (stub)."""

from __future__ import annotations

from datetime import datetime
from typing import Dict, List, Optional

from app.services.trading.exchange.base import AbstractExchange
from app.services.trading.models import Candle


class BybitExchange(AbstractExchange):
    """Bybit exchange connector.

    API docs: https://bybit-exchange.github.io/docs/v5/intro
    """

    def __init__(self, api_key: str = "", api_secret: str = "") -> None:
        super().__init__(name="bybit", api_key=api_key, api_secret=api_secret)

    async def get_klines(
        self,
        pair: str,
        timeframe: str,
        start: Optional[datetime] = None,
        end: Optional[datetime] = None,
        limit: int = 500,
    ) -> List[Candle]:
        """Fetch historical klines from Bybit."""
        # TODO: implement Bybit API v5 GET /v5/market/kline
        return []

    async def get_ticker(self, pair: str) -> Dict[str, float]:
        """Fetch current ticker from Bybit."""
        # TODO: implement Bybit API v5 GET /v5/market/tickers
        return {}

    async def place_order(
        self,
        pair: str,
        side: str,
        quantity: float,
        order_type: str = "market",
        price: Optional[float] = None,
    ) -> Dict:
        """Place order on Bybit."""
        # TODO: implement Bybit API v5 POST /v5/order/create
        return {}

    async def get_balance(self, currency: str = "") -> Dict[str, float]:
        """Fetch wallet balance from Bybit."""
        # TODO: implement Bybit API v5 GET /v5/account/wallet-balance
        return {}
