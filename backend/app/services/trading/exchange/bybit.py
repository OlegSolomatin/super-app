"""Bybit exchange connector — fetches real historical data via public API v5.

API docs: https://bybit-exchange.github.io/docs/v5/market/kline
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

BYBIT_BASE_URL = "https://api.bybit.com"
MAX_LIMIT = 200  # Bybit max candles per request

# Bybit interval format: https://bybit-exchange.github.io/docs/v5/market/kline
TIMEFRAME_MAP = {
    "1m": "1",
    "3m": "3",
    "5m": "5",
    "15m": "15",
    "30m": "30",
    "1h": "60",
    "2h": "120",
    "4h": "240",
    "6h": "360",
    "12h": "720",
    "1d": "D",
    "1w": "W",
    "1M": "M",
}


class BybitExchange(AbstractExchange):
    """Bybit exchange connector.

    Fetches real historical OHLCV data via Bybit public REST API v5.
    """

    def __init__(self, api_key: str = "", api_secret: str = "") -> None:
        super().__init__(name="bybit", api_key=api_key, api_secret=api_secret)
        self._session: Optional[aiohttp.ClientSession] = None

    async def _get_session(self) -> aiohttp.ClientSession:
        if self._session is None or self._session.closed:
            self._session = aiohttp.ClientSession(
                timeout=aiohttp.ClientTimeout(total=30),
                headers={"Accept": "application/json"},
            )
        return self._session

    def _map_timeframe(self, tf: str) -> str:
        """Convert internal timeframe to Bybit API format."""
        mapped = TIMEFRAME_MAP.get(tf)
        if mapped is None:
            logger.warning("Unknown timeframe '%s', falling back to 60 (1h)", tf)
            return "60"
        return mapped

    async def get_klines(
        self,
        pair: str,
        timeframe: str,
        start: Optional[datetime] = None,
        end: Optional[datetime] = None,
        limit: int = 200,
    ) -> List[Candle]:
        """Fetch historical klines from Bybit public API v5.

        Handles pagination backwards for ranges larger than 200 candles.
        Returns candles sorted chronologically (oldest first).
        """
        session = await self._get_session()
        candles: List[Candle] = []

        interval = self._map_timeframe(timeframe)

        now = datetime.now(timezone.utc)
        end_dt = (end or now).astimezone(timezone.utc)
        start_dt = start.astimezone(timezone.utc) if start else end_dt

        current_end = int(end_dt.timestamp() * 1000)
        start_ms = int(start_dt.timestamp() * 1000)
        fetch_limit = min(limit, MAX_LIMIT)

        fetch_count = 0
        max_requests = 100

        while current_end > start_ms and fetch_count < max_requests:
            fetch_count += 1

            params: Dict[str, str | int] = {
                "category": "spot",
                "symbol": pair.upper(),
                "interval": interval,
                "limit": fetch_limit,
            }

            # Bybit uses start/end in milliseconds (end is exclusive)
            params["end"] = str(current_end)

            try:
                async with session.get(
                    f"{BYBIT_BASE_URL}/v5/market/kline",
                    params=params,
                ) as resp:
                    if resp.status == 429:
                        retry_after = 5
                        logger.warning("Bybit rate limited, waiting %ds", retry_after)
                        await asyncio.sleep(retry_after)
                        continue

                    if resp.status != 200:
                        text = await resp.text()
                        logger.error("Bybit API error %d: %s", resp.status, text)
                        break

                    data = await resp.json()
                    if data.get("retCode") != 0:
                        logger.error("Bybit API retCode %s: %s", data.get("retCode"), data.get("retMsg"))
                        break

                    result_list = data.get("result", {}).get("list", [])
                    if not result_list:
                        break

                    # Bybit returns newest first — reverse to oldest-first
                    result_list.reverse()

                    for entry in result_list:
                        ts = datetime.fromtimestamp(int(entry[0]) / 1000, tz=timezone.utc)
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

                    # Move cursor backward
                    first_ts = int(result_list[0][0])
                    current_end = first_ts - 1

                    await asyncio.sleep(0.1)

            except asyncio.TimeoutError:
                logger.warning("Bybit request timed out, retrying...")
                await asyncio.sleep(1)
                continue
            except aiohttp.ClientError as e:
                logger.error("Bybit HTTP error: %s", e)
                break

        # Sort chronologically — Bybit returns newest first
        candles.sort(key=lambda c: c.timestamp)

        logger.info(
            "Bybit: fetched %d candles for %s %s [%s – %s]",
            len(candles),
            pair,
            timeframe,
            candles[0].timestamp if candles else "N/A",
            candles[-1].timestamp if candles else "N/A",
        )
        return candles

    async def get_ticker(self, pair: str) -> Dict[str, float]:
        """Fetch current ticker from Bybit public API."""
        session = await self._get_session()
        try:
            async with session.get(
                f"{BYBIT_BASE_URL}/v5/market/tickers",
                params={"category": "spot", "symbol": pair.upper()},
            ) as resp:
                if resp.status == 200:
                    data = await resp.json()
                    if data.get("retCode") == 0:
                        t = data["result"]["list"][0]
                        return {
                            "last": float(t.get("lastPrice", 0)),
                            "volume": float(t.get("volume24h", 0)),
                            "high": float(t.get("highPrice24h", 0)),
                            "low": float(t.get("lowPrice24h", 0)),
                            "bid": float(t.get("bid1Price", 0)),
                            "ask": float(t.get("ask1Price", 0)),
                        }
        except Exception as e:
            logger.error("Bybit ticker error: %s", e)
        return {}

    def _sign_request(self, timestamp: str, recv_window: str, body: str = "") -> str:
        """Create Bybit v5 HMAC-SHA256 signature.

        sign_string = timestamp + api_key + recv_window + body
        """
        import hashlib
        import hmac

        sign_string = timestamp + self.api_key + recv_window + body
        signature = hmac.new(
            self.api_secret.encode("utf-8"),
            sign_string.encode("utf-8"),
            hashlib.sha256,
        ).hexdigest()
        return signature

    async def place_order(
        self,
        pair: str,
        side: str,
        quantity: float,
        order_type: str = "market",
        price: Optional[float] = None,
    ) -> Dict:
        """Place REAL order on Bybit via signed API v5.

        Requires api_key and api_secret to be set.
        Uses HMAC-SHA256 signature in header.
        """
        if not self.api_key or not self.api_secret:
            logger.warning("Bybit place_order: no API keys configured")
            return {"error": "No API keys configured", "status": "REJECTED"}

        import json
        import time

        session = await self._get_session()

        ts = str(int(time.time() * 1000))
        recv_window = "5000"

        body = {
            "category": "spot",
            "symbol": pair.upper(),
            "side": side.capitalize(),
            "orderType": order_type.capitalize(),
            "qty": str(quantity),
            "timeInForce": "IOC",
        }
        if order_type.lower() == "limit" and price is not None:
            body["orderType"] = "Limit"
            body["price"] = str(price)
            body["timeInForce"] = "GTC"

        body_json = json.dumps(body, separators=(",", ":"))
        sign = self._sign_request(ts, recv_window, body_json)

        headers = {
            "X-BAPI-API-KEY": self.api_key,
            "X-BAPI-TIMESTAMP": ts,
            "X-BAPI-SIGN": sign,
            "X-BAPI-RECV-WINDOW": recv_window,
            "Content-Type": "application/json",
        }

        try:
            async with session.post(
                f"{BYBIT_BASE_URL}/v5/order/create",
                data=body_json,
                headers=headers,
            ) as resp:
                data = await resp.json()
                if resp.status == 200 and data.get("retCode") == 0:
                    result = data.get("result", {})
                    order_id = result.get("orderId", "")
                    logger.info(
                        "Bybit order placed: %s %s %s %s (orderId=%s)",
                        side, quantity, pair, order_type, order_id,
                    )
                    # Parse fills for actual fill price/qty
                    fills_list = result.get("fills", [])
                    fill_qty = sum(
                        float(f.get("qty", 0)) for f in fills_list
                    ) if fills_list else float(quantity)
                    fill_price = 0.0
                    if fills_list:
                        fill_price = sum(
                            float(f.get("qty", 0)) * float(f.get("price", 0))
                            for f in fills_list
                        ) / fill_qty if fill_qty > 0 else 0.0
                    return {
                        "order_id": order_id,
                        "symbol": result.get("symbol", pair.upper()),
                        "side": side,
                        "quantity": fill_qty,
                        "price": fill_price or float(result.get("price", "0")),
                        "status": result.get("orderStatus", "FILLED"),
                        "fills": fills_list,
                    }
                else:
                    logger.error(
                        "Bybit order error %d: %s", resp.status, data
                    )
                    return {
                        "error": data.get("retMsg", str(data)),
                        "status": "REJECTED",
                        "code": resp.status,
                    }
        except Exception as e:
            logger.error("Bybit order exception: %s", e)
            return {"error": str(e), "status": "REJECTED"}

    async def get_balance(self, currency: str = "") -> Dict[str, float]:
        """Fetch REAL wallet balance from Bybit via signed API v5.

        Returns dict of {currency: amount, ...}.
        If currency is specified, only that currency is returned.
        """
        if not self.api_key or not self.api_secret:
            logger.warning("Bybit get_balance: no API keys configured")
            return {}

        import time

        session = await self._get_session()
        ts = str(int(time.time() * 1000))
        recv_window = "5000"
        sign = self._sign_request(ts, recv_window)

        headers = {
            "X-BAPI-API-KEY": self.api_key,
            "X-BAPI-TIMESTAMP": ts,
            "X-BAPI-SIGN": sign,
            "X-BAPI-RECV-WINDOW": recv_window,
        }

        params = {"accountType": "UNIFIED", "coin": currency.upper()} if currency else {"accountType": "UNIFIED"}

        try:
            async with session.get(
                f"{BYBIT_BASE_URL}/v5/account/wallet-balance",
                params=params,
                headers=headers,
            ) as resp:
                if resp.status == 200:
                    data = await resp.json()
                    if data.get("retCode") == 0:
                        coin_list = (
                            data.get("result", {})
                            .get("list", [{}])[0]
                            .get("coin", [])
                        )
                        result: Dict[str, float] = {}
                        for coin in coin_list:
                            coin_name = coin.get("coin", "")
                            wallet_balance = float(coin.get("walletBalance", "0"))
                            if wallet_balance > 0 or (
                                currency and coin_name.upper() == currency.upper()
                            ):
                                result[coin_name.upper()] = wallet_balance
                        logger.info(
                            "Bybit balance: %s", result
                        )
                        return result
                    logger.warning(
                        "Bybit balance error: retCode=%s retMsg=%s",
                        data.get("retCode"), data.get("retMsg"),
                    )
                else:
                    text = await resp.text()
                    logger.error("Bybit balance HTTP %d: %s", resp.status, text)
        except Exception as e:
            logger.error("Bybit balance exception: %s", e)
        return {}

    async def close(self) -> None:
        """Close the HTTP session."""
        if self._session and not self._session.closed:
            await self._session.close()
