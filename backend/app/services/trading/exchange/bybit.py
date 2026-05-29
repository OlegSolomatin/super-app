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

    async def place_order(
        self,
        pair: str,
        side: str,
        quantity: float,
        order_type: str = "market",
        price: Optional[float] = None,
    ) -> Dict:
        """Place order on Bybit (requires API keys — not implemented for public API)."""
        logger.warning("Bybit place_order requires authenticated API — use real mode with API keys")
        return {
            "order_id": "",
            "symbol": pair,
            "side": side,
            "quantity": quantity,
            "price": price or 0.0,
            "status": "REJECTED",
            "error": "Real trading requires API keys configured",
        }

    async def get_balance(self, currency: str = "") -> Dict[str, float]:
        """Fetch wallet balance (requires API keys — not implemented for public API)."""
        logger.warning("Bybit get_balance requires authenticated API — use real mode with API keys")
        return {}

    async def close(self) -> None:
        """Close the HTTP session."""
        if self._session and not self._session.closed:
            await self._session.close()
