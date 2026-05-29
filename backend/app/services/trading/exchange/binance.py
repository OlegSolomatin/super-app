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
        """Place order on Binance (requires API keys — not implemented for public API)."""
        logger.warning("Binance place_order requires authenticated API — use real mode with API keys")
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
        """Fetch account balance (requires API keys — not implemented for public API)."""
        logger.warning("Binance get_balance requires authenticated API — use real mode with API keys")
        return {}

    async def close(self) -> None:
        """Close the HTTP session."""
        if self._session and not self._session.closed:
            await self._session.close()
