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

from app.services.trading.orderbook.data.base import DataProvider
from app.services.trading.orderbook.models import OrderBookSnapshot

logger = logging.getLogger(__name__)

BINANCE_WS_BASE = "wss://stream.binance.com:9443"
DEPTH_STREAM_TEMPLATE = "{symbol}@depth20@100ms"


class BinanceDataProvider(DataProvider):
    """WebSocket клиент для получения стакана с Binance.

    Наследует DataProvider (единый интерфейс для всех бирж).
    При разрыве — reconnect с exponential backoff.
    """

    def __init__(self, pairs: list[str]):
        super().__init__(pairs)
        self._ws: Optional[aiohttp.ClientWebSocketResponse] = None
        self._reconnect_delay = 1.0

    @property
    def name(self) -> str:
        return "binance"

    def _stream_for_pair(self, pair: str) -> str:
        """Генерирует stream name для любой пары Binance."""
        return DEPTH_STREAM_TEMPLATE.format(symbol=pair.lower())

    async def start(
        self,
        callback: Callable[[OrderBookSnapshot],
                           Coroutine[Any, Any, None]],
    ) -> None:
        """Запустить WS и слушать до остановки.

        DataProvider: реализация абстрактного метода start().
        ccxt Pro: Client.connect() + watch()
        """
        self._callback = callback
        self._running = True

        if not self._pairs:
            logger.error("[BinanceDataProvider] No pairs configured, cannot start")
            return

        while self._running:
            try:
                await self._connect_and_listen()
            except Exception as e:
                if not self._running:
                    break
                logger.warning(
                    f"[BinanceDataProvider] Error: {e}. "
                    f"Reconnect in {self._reconnect_delay}s..."
                )
                await asyncio.sleep(self._reconnect_delay)
                self._reconnect_delay = min(self._reconnect_delay * 2, 60.0)

    async def _connect_and_listen(self):
        """Подключиться к Binance WS и слушать поток стакана."""
        streams = [self._stream_for_pair(p) for p in self._pairs]

        if not streams:
            raise ValueError("No pairs configured for Binance stream")

        url = f"{BINANCE_WS_BASE}/stream?streams={'/'.join(streams)}"
        logger.info(f"[BinanceDataProvider] Connecting ({len(streams)} stream(s))")

        async with aiohttp.ClientSession(
            timeout=aiohttp.ClientTimeout(total=30)
        ) as session:
            try:
                async with session.ws_connect(url, heartbeat=30.0) as ws:
                    self._ws = ws
                    self._reconnect_delay = 1.0
                    logger.info(f"[BinanceDataProvider] Connected ({len(streams)} streams)")

                    async for msg in ws:
                        if not self._running:
                            break
                        if msg.type == aiohttp.WSMsgType.TEXT:
                            await self._on_message(msg.data)
                        elif msg.type in (
                            aiohttp.WSMsgType.CLOSED,
                            aiohttp.WSMsgType.ERROR,
                        ):
                            break
            except asyncio.TimeoutError:
                logger.warning("[BinanceDataProvider] WS connection timeout, will reconnect")
                raise
            except Exception as e:
                logger.warning(f"[BinanceDataProvider] WS connection error: {e}")
                raise

    async def _on_message(self, raw: str):
        """Парсинг сообщения -> OrderBookSnapshot.

        @depth20@100ms: {stream, data{lastUpdateId, bids, asks}}
        """
        try:
            msg = json.loads(raw)
            data = msg.get("data", msg)
            has_snapshot = "lastUpdateId" in data or "bids" in data or "asks" in data
            pair = data.get("s", "")

            if has_snapshot and not pair:
                stream_name = msg.get("stream", "")
                if stream_name:
                    pair = stream_name.split("@")[0].upper()
                if not pair and self._pairs:
                    pair = self._pairs[0].upper()

            bids_raw = data.get("bids", data.get("b", []))
            asks_raw = data.get("asks", data.get("a", []))

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
            if self._callback:
                await self._callback(snap)
        except (json.JSONDecodeError, KeyError, ValueError, TypeError) as e:
            logger.debug(f"[BinanceDataProvider] Parse error: {e}")

    async def stop(self):
        """DataProvider: остановить получение данных."""
        self._running = False
        if self._ws and not self._ws.closed:
            await self._ws.close()
        logger.info("[BinanceDataProvider] Stopped")
