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
DEPTH_STREAM_TEMPLATE = "{symbol}@depth20@100ms"


# Known stream names (used for logging/diagnostic only; generation is dynamic)
# Any symbol is supported via DEPTH_STREAM_TEMPLATE
SUPPORTED_STREAMS = frozenset({
    "BTCUSDT", "ETHUSDT", "SOLUSDT", "TONUSDT", "BNBUSDT",
    "NEARUSDT", "XRPUSDT", "ADAUSDT", "DOGEUSDT", "AVAXUSDT",
    "DOTUSDT", "LTCUSDT", "LINKUSDT", "UNIUSDT", "ATOMUSDT",
    "TRXUSDT", "XLMUSDT", "ALGOUSDT", "FTMUSDT", "SANDUSDT",
    "SHIBUSDT", "MATICUSDT", "APTUSDT", "ARBUSDT", "OPUSDT",
    "SUIUSDT", "SEIUSDT", "INJUSDT", "TIAUSDT", "PEPEUSDT",
    "WIFUSDT", "BONKUSDT", "AAVEUSDT", "FILUSDT", "ETCUSDT",
})


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

    def _stream_for_pair(self, pair: str) -> str:
        """Генерирует stream name для любой пары Binance."""
        return DEPTH_STREAM_TEMPLATE.format(symbol=pair.lower())

    async def start(self):
        """Запустить WS и слушать до остановки.

        ccxt Pro: Client.connect() + watch()
        """
        self._running = True

        # Проверка: есть ли хоть одна пара для подключения
        if not self._pairs:
            logger.error("[OBFetcher] No pairs configured, cannot start")
            return

        unsupported = [p for p in self._pairs if p.upper() not in SUPPORTED_STREAMS]
        if unsupported:
            logger.warning(
                f"[OBFetcher] Pairs {unsupported} are not in KNOWN set. "
                f"They are dynamically generated via Binance stream template "
                f"and may not have data for all snapshots/depths."
            )

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
        """Подключиться к Binance WS и слушать поток стакана."""
        # Всегда генерируем stream name динамически — любая пара работает
        streams = [self._stream_for_pair(p) for p in self._pairs]

        if not streams:
            logger.error(f"[OBFetcher] No pairs configured: {self._pairs}")
            # Бросаем исключение, чтобы start() сделал паузу с backoff
            raise ValueError("No pairs configured for Binance stream")

        url = f"{BINANCE_WS_BASE}/stream?streams={'/'.join(streams)}"
        logger.info(f"[OBFetcher] Connecting to Binance WS ({len(streams)} stream(s))")

        async with aiohttp.ClientSession(timeout=aiohttp.ClientTimeout(total=30)) as session:
            try:
                async with session.ws_connect(
                    url,
                    heartbeat=30.0,
                ) as ws:
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
            except asyncio.TimeoutError:
                logger.warning("[OBFetcher] WS connection timeout, will reconnect")
                raise
            except Exception as e:
                logger.warning(f"[OBFetcher] WS connection error: {e}")
                raise

    async def _on_message(self, raw: str):
        """Парсинг сообщения -> OrderBookSnapshot.

        The @depth20@100ms stream returns snapshots (not diffs):
          {
            "stream": "btcusdt@depth20@100ms",
            "data": { "lastUpdateId": N, "bids": [["p","q"],...], "asks": [...] }
          }
        """
        try:
            msg = json.loads(raw)
            data = msg.get("data", msg)
            # depth20@100ms uses "lastUpdateId" + "bids"/"asks" (not "s"/"b"/"a")
            has_snapshot = "lastUpdateId" in data or "bids" in data or "asks" in data
            pair = data.get("s", "")

            if has_snapshot and not pair:
                # Extract pair from stream name: "btcusdt@depth20@100ms" -> "BTCUSDT"
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
            await self._callback(snap)
        except (json.JSONDecodeError, KeyError, ValueError, TypeError) as e:
            logger.debug(f"[OBFetcher] Parse error: {e}")

    async def stop(self):
        self._running = False
        if self._ws and not self._ws.closed:
            await self._ws.close()
        logger.info("[OBFetcher] Stopped")
