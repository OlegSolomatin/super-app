"""Binance exchange connector — fetches real historical data via public API.

API docs: https://binance-docs.github.io/apidocs/spot/en/#kline-candlestick-data
Public endpoints — no API keys required for klines/ticker.
"""

from __future__ import annotations

import asyncio
import logging
from datetime import datetime, timezone
from typing import Dict, List, Optional

import aiohttp

from app.services.trading.exchange.base import AbstractExchange
from app.services.trading.models import Candle

logger = logging.getLogger(__name__)

BINANCE_BASE_URL = "https://api.binance.com"
MAX_LIMIT = 1000  # Max candles per request


class BinanceExchange(AbstractExchange):
    """Binance exchange connector.

    Fetches real historical OHLCV data via Binance public REST API.
    """

    def __init__(self, api_key: str = "", api_secret: str = "") -> None:
        super().__init__(name="binance", api_key=api_key, api_secret=api_secret)
        self._session: Optional[aiohttp.ClientSession] = None

    async def _get_session(self) -> aiohttp.ClientSession:
        """Get or create a reusable HTTP session."""
        if self._session is None or self._session.closed:
            self._session = aiohttp.ClientSession(
                timeout=aiohttp.ClientTimeout(total=30),
                headers={"Accept": "application/json"},
            )
        return self._session

    async def get_klines(
        self,
        pair: str,
        timeframe: str,
        start: Optional[datetime] = None,
        end: Optional[datetime] = None,
        limit: int = 500,
    ) -> List[Candle]:
        """Fetch historical klines from Binance public API.

        Handles pagination for ranges larger than 1000 candles.
        Returns candles sorted chronologically (oldest first).
        """
        session = await self._get_session()
        candles: List[Candle] = []

        # Convert to millisecond timestamps
        end_ms = int((end or datetime.now(timezone.utc)).timestamp() * 1000)
        start_ms = int(start.timestamp() * 1000) if start else end_ms - (limit * 60 * 60 * 1000)

        params = {
            "symbol": pair.upper(),
            "interval": timeframe,
            "limit": min(limit, MAX_LIMIT),
        }

        current_end = end_ms
        fetch_count = 0
        max_requests = 100  # Safety limit

        while current_end > start_ms and fetch_count < max_requests:
            fetch_count += 1
            params["endTime"] = current_end
            params["startTime"] = start_ms

            try:
                async with session.get(
                    f"{BINANCE_BASE_URL}/api/v3/klines",
                    params=params,
                ) as resp:
                    if resp.status == 429:
                        retry_after = int(resp.headers.get("Retry-After", "5"))
                        logger.warning("Binance rate limited, waiting %ds", retry_after)
                        await asyncio.sleep(retry_after)
                        continue

                    if resp.status != 200:
                        text = await resp.text()
                        logger.error("Binance API error %d: %s", resp.status, text)
                        break

                    data = await resp.json()
                    if not data:
                        break

                    # Parse candles from response
                    for entry in data:
                        ts = datetime.fromtimestamp(entry[0] / 1000, tz=timezone.utc)
                        candles.append(
                            Candle(
                                open=float(entry[1]),
                                high=float(entry[2]),
                                low=float(entry[3]),
                                close=float(entry[4]),
                                volume=float(entry[5]),
                                timestamp=ts,
                            )
                        )

                    # Move cursor back for next page
                    first_ts = data[0][0]
                    current_end = first_ts - 1

                    # Small delay to avoid rate limiting
                    await asyncio.sleep(0.1)

            except asyncio.TimeoutError:
                logger.warning("Binance request timed out, retrying...")
                await asyncio.sleep(1)
                continue
            except aiohttp.ClientError as e:
                logger.error("Binance HTTP error: %s", e)
                break

        # Filter by time range and sort
        if start:
            _start = start.replace(tzinfo=timezone.utc) if start.tzinfo is None else start
            candles = [c for c in candles if c.timestamp >= _start]
        if end:
            _end = end.replace(tzinfo=timezone.utc) if end.tzinfo is None else end
            candles = [c for c in candles if c.timestamp <= _end]

        candles.sort(key=lambda c: c.timestamp)
        logger.info(
            "Binance: fetched %d candles for %s %s [%s – %s]",
            len(candles),
            pair,
            timeframe,
            candles[0].timestamp if candles else "N/A",
            candles[-1].timestamp if candles else "N/A",
        )
        return candles

    async def get_ticker(self, pair: str) -> Dict[str, float]:
        """Fetch current ticker from Binance public API."""
        session = await self._get_session()
        try:
            async with session.get(
                f"{BINANCE_BASE_URL}/api/v3/ticker/24hr",
                params={"symbol": pair.upper()},
            ) as resp:
                if resp.status == 200:
                    data = await resp.json()
                    return {
                        "last": float(data.get("lastPrice", 0)),
                        "volume": float(data.get("volume", 0)),
                        "high": float(data.get("highPrice", 0)),
                        "low": float(data.get("lowPrice", 0)),
                        "bid": float(data.get("bidPrice", 0)),
                        "ask": float(data.get("askPrice", 0)),
                    }
        except Exception as e:
            logger.error("Binance ticker error: %s", e)
        return {}

    async def place_order(
        self,
        pair: str,
        side: str,
        quantity: float,
        order_type: str = "market",
        price: Optional[float] = None,
    ) -> Dict:
        """Place a REAL order on Binance via signed API.

        Requires api_key and api_secret to be set.
        Uses HMAC-SHA256 signature with timestamp + recvWindow.
        """
        if not self.api_key or not self.api_secret:
            logger.warning("Binance place_order: no API keys configured")
            return {"error": "No API keys configured", "status": "REJECTED"}

        import hmac
        import hashlib
        import time

        session = await self._get_session()

        params: Dict[str, str] = {
            "symbol": pair.upper(),
            "side": side.upper(),
            "type": order_type.upper(),
            "quantity": str(quantity),
            "timestamp": str(int(time.time() * 1000)),
            "recvWindow": "5000",
        }
        if order_type.lower() == "limit" and price is not None:
            params["price"] = str(price)
            params["timeInForce"] = "GTC"

        # Generate HMAC-SHA256 signature
        query_string = "&".join(f"{k}={v}" for k, v in sorted(params.items()))
        signature = hmac.new(
            self.api_secret.encode("utf-8"),
            query_string.encode("utf-8"),
            hashlib.sha256,
        ).hexdigest()
        params["signature"] = signature

        headers = {"X-MBX-APIKEY": self.api_key}

        try:
            async with session.post(
                f"{BINANCE_BASE_URL}/api/v3/order",
                params=params,
                headers=headers,
            ) as resp:
                data = await resp.json()
                if resp.status == 200:
                    logger.info(
                        "Binance order placed: %s %s %s %s (orderId=%s)",
                        side, quantity, pair, order_type,
                        data.get("orderId", "?"),
                    )
                    return {
                        "order_id": str(data.get("orderId", "")),
                        "symbol": data.get("symbol", pair),
                        "side": data.get("side", side),
                        "quantity": float(data.get("executedQty", quantity)),
                        "price": float(data.get("price", price or 0)),
                        "status": data.get("status", "FILLED"),
                        "fills": data.get("fills", []),
                    }
                else:
                    logger.error(
                        "Binance order error %d: %s", resp.status, data
                    )
                    return {
                        "error": data.get("msg", str(data)),
                        "status": "REJECTED",
                        "code": resp.status,
                    }
        except Exception as e:
            logger.error("Binance order exception: %s", e)
            return {"error": str(e), "status": "REJECTED"}

    async def get_balance(self, currency: str = "") -> Dict[str, float]:
        """Fetch REAL account balance from Binance via signed API.

        Requires api_key and api_secret to be set.
        If currency is specified, returns only that asset's data.
        """
        if not self.api_key or not self.api_secret:
            logger.warning("Binance get_balance: no API keys configured")
            return {}

        import hmac
        import hashlib
        import time

        session = await self._get_session()

        params = {
            "timestamp": str(int(time.time() * 1000)),
            "recvWindow": "5000",
        }
        query_string = "&".join(f"{k}={v}" for k, v in sorted(params.items()))
        signature = hmac.new(
            self.api_secret.encode("utf-8"),
            query_string.encode("utf-8"),
            hashlib.sha256,
        ).hexdigest()
        params["signature"] = signature

        headers = {"X-MBX-APIKEY": self.api_key}

        try:
            async with session.get(
                f"{BINANCE_BASE_URL}/api/v3/account",
                params=params,
                headers=headers,
            ) as resp:
                data = await resp.json()
                if resp.status == 200:
                    balances = {}
                    for asset in data.get("balances", []):
                        free = float(asset.get("free", 0))
                        locked = float(asset.get("locked", 0))
                        total = free + locked
                        if total > 0:
                            if not currency or asset["asset"].upper() == currency.upper():
                                balances[asset["asset"]] = total
                                balances[f"{asset['asset']}_free"] = free
                                balances[f"{asset['asset']}_locked"] = locked

                    if currency:
                        cur = currency.upper()
                        logger.info(
                            "Binance balance: %s = %.2f (free=%.2f, locked=%.2f)",
                            cur,
                            balances.get(cur, 0),
                            balances.get(f"{cur}_free", 0),
                            balances.get(f"{cur}_locked", 0),
                        )
                    return balances
                else:
                    logger.error(
                        "Binance account error %d: %s", resp.status, data
                    )
                    return {}
        except Exception as e:
            logger.error("Binance get_balance exception: %s", e)
            return {}

    async def get_orderbook(
        self,
        pair: str,
        limit: int = 20,
    ) -> Dict:
        """Fetch current order book from Binance public API."""
        session = await self._get_session()
        try:
            async with session.get(
                f"{BINANCE_BASE_URL}/api/v3/depth",
                params={"symbol": pair.upper(), "limit": limit},
            ) as resp:
                if resp.status == 200:
                    data = await resp.json()
                    return {
                        "bids": data.get("bids", []),
                        "asks": data.get("asks", []),
                        "timestamp": data.get("lastUpdateId", 0),
                    }
        except Exception as e:
            logger.error("Binance orderbook error: %s", e)
        return {"bids": [], "asks": [], "timestamp": 0}

    async def close(self) -> None:
        """Close the HTTP session."""
        if self._session and not self._session.closed:
            await self._session.close()
