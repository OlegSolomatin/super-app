"""WebSocket поток стакана Binance.

ccxt Pro: client.py + order_book.py (snapshot+diff sync)

Binance depth stream:
  wss://stream.binance.com:9443/ws/<stream>@depth20@100ms
Combined:
  wss://stream.binance.com:9443/stream?streams=<s1>/<s2>
"""
from __future__ import annotations

import asyncio
import json
import logging
from datetime import datetime, timezone
from typing import Any, Callable, Coroutine, Optional

import aiohttp

from app.services.trading.orderbook.models import OrderBookSnapshot

logger = logging.getLogger(__name__)

BINANCE_WS_BASE = "wss://stream.binance.com:9443"

SYMBOL_TO_STREAM = {
    "BTCUSDT": "btcusdt@depth20@100ms",
    "ETHUSDT": "ethusdt@depth20@100ms",
    "SOLUSDT": "solusdt@depth20@100ms",
    "TONUSDT": "tonusdt@depth20@100ms",
    "BNBUSDT": "bnbusdt@depth20@100ms",
}


class BinanceOrderBookStream:
    """WebSocket клиент для получения стакана с Binance.

    При разрыве — reconnect с exponential backoff.
    """

    def __init__(self, pairs: list[str],
                 on_snapshot: Callable[[OrderBookSnapshot],
                                       Coroutine[Any, Any, None]]):
        self._pairs = pairs
        self._callback = on_snapshot
        self._ws = None
        self._running = False
        self._reconnect_delay = 1.0

    async def start(self):
        """Запустить WS и слушать до остановки.

        ccxt Pro: Client.connect() + watch()
        """
        self._running = True
        while self._running:
            try:
                await self._connect_and_listen()
            except Exception as e:
                if not self._running:
                    break
                logger.warning(
                    f"[OBFetcher] Error: {e}. "
                    f"Reconnect in {self._reconnect_delay}s..."
                )
                await asyncio.sleep(self._reconnect_delay)
                self._reconnect_delay = min(self._reconnect_delay * 2, 60.0)

    async def _connect_and_listen(self):
        streams = [
            SYMBOL_TO_STREAM[p.upper()]
            for p in self._pairs
            if p.upper() in SYMBOL_TO_STREAM
        ]
        if not streams:
            logger.error(f"[OBFetcher] No known pairs: {self._pairs}")
            return

        url = f"{BINANCE_WS_BASE}/stream?streams={'/'.join(streams)}"
        logger.info(f"[OBFetcher] Connecting to {url}")

        async with aiohttp.ClientSession() as session:
            async with session.ws_connect(url, heartbeat=30.0) as ws:
                self._ws = ws
                self._reconnect_delay = 1.0
                logger.info(f"[OBFetcher] Connected ({len(streams)} streams)")

                async for msg in ws:
                    if not self._running:
                        break
                    if msg.type == aiohttp.WSMsgType.TEXT:
                        await self._on_message(msg.data)
                    elif msg.type in (aiohttp.WSMsgType.CLOSED,
                                      aiohttp.WSMsgType.ERROR):
                        break

    async def _on_message(self, raw: str):
        """Парсинг сообщения -> OrderBookSnapshot.

        ccxt: parse_order_book()
        """
        try:
            msg = json.loads(raw)
            data = msg.get("data", msg)
            pair = data.get("s", "")
            bids_raw = data.get("b", [])
            asks_raw = data.get("a", [])
            if not pair or not bids_raw or not asks_raw:
                return
            bids = [(float(p), float(q)) for p, q in bids_raw if float(q) > 0]
            asks = [(float(p), float(q)) for p, q in asks_raw if float(q) > 0]
            snap = OrderBookSnapshot(
                pair=pair,
                timestamp=datetime.now(timezone.utc),
                bids=bids,
                asks=asks,
            )
            await self._callback(snap)
        except (json.JSONDecodeError, KeyError, ValueError, TypeError) as e:
            logger.debug(f"[OBFetcher] Parse error: {e}")

    async def stop(self):
        self._running = False
        if self._ws and not self._ws.closed:
            await self._ws.close()
        logger.info("[OBFetcher] Stopped")
