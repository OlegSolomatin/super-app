"""Mock exchange connector for development and testing.

Simulates exchange behaviour using in-memory data.
"""

from __future__ import annotations

import random
from datetime import datetime, timedelta
from typing import Dict, List, Optional

from app.services.trading.exchange.base import AbstractExchange
from app.services.trading.models import Candle


class MockExchange(AbstractExchange):
    """Mock exchange that generates synthetic candle data.

    Useful for development and unit testing without live API calls.
    """

    def __init__(self) -> None:
        super().__init__(name="mock")

    async def get_klines(
        self,
        pair: str,
        timeframe: str,
        start: Optional[datetime] = None,
        end: Optional[datetime] = None,
        limit: int = 500,
    ) -> List[Candle]:
        """Return randomly generated candles in the requested time range."""
        candles: List[Candle] = []
        now = datetime.now()
        base_price = 50000.0
        end_dt = end or now
        start_dt = start or (end_dt - timedelta(hours=limit))
        # Generate candles from end_dt backwards
        for i in range(limit):
            ts = end_dt - timedelta(hours=i)
            if ts < start_dt:
                break
            change = random.uniform(-200, 200)
            open_price = base_price + change
            close_price = open_price + random.uniform(-100, 100)
            high = max(open_price, close_price) + random.uniform(0, 50)
            low = min(open_price, close_price) - random.uniform(0, 50)
            volume = random.uniform(10, 1000)
            candles.append(
                Candle(
                    open=round(open_price, 2),
                    high=round(high, 2),
                    low=round(low, 2),
                    close=round(close_price, 2),
                    volume=round(volume, 4),
                    timestamp=ts,
                )
            )
        return candles[::-1]  # Return in chronological order

    async def get_ticker(self, pair: str) -> Dict[str, float]:
        """Return a simulated ticker."""
        return {"last": 50000.0, "volume": 1234.5, "high": 51000.0, "low": 49000.0}

    async def place_order(
        self,
        pair: str,
        side: str,
        quantity: float,
        order_type: str = "market",
        price: Optional[float] = None,
    ) -> Dict:
        """Simulate placing an order."""
        return {
            "order_id": "mock_order_123",
            "symbol": pair,
            "side": side,
            "quantity": quantity,
            "price": price or 50000.0,
            "status": "FILLED",
        }

    async def get_balance(self, currency: str = "") -> Dict[str, float]:
        """Return a simulated balance."""
        return {"USDT": 10000.0, "BTC": 0.5, "ETH": 2.0}

    async def get_orderbook(
        self,
        pair: str,
        limit: int = 20,
    ) -> Dict:
        """Return a simulated order book."""
        import random
        base = 50000.0
        bids = [[base - i * 10, random.uniform(0.1, 5.0)] for i in range(limit)]
        asks = [[base + i * 10, random.uniform(0.1, 5.0)] for i in range(limit)]
        return {"bids": bids, "asks": asks, "timestamp": 0}
