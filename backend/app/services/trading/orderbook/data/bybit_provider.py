"""WebSocket поток стакана Bybit.

Bybit WebSocket v5:
  Public spot: wss://stream.bybit.com/v5/public/spot
  Public linear: wss://stream.bybit.com/v5/public/linear
  Topic: orderbook.200.100ms.{symbol}

Формат снапшота:
  {
    "topic": "orderbook.200.100ms.BTCUSDT",
    "type": "snapshot",
    "data": {
      "s": "BTCUSDT",
      "b": [["price","qty"],...],
      "a": [["price","qty"],...],
      "u": 123,
      "seq": 456
    }
  }

ccxt Pro: bybit.watch_order_book() — единый интерфейс.
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

BYBIT_WS_SPOT = "wss://stream.bybit.com/v5/public/spot"
BYBIT_WS_LINEAR = "wss://stream.bybit.com/v5/public/linear"
ORDERBOOK_TOPIC_TEMPLATE = "orderbook.200.100ms.{symbol}"


class BybitDataProvider(DataProvider):
    """WebSocket клиент для получения стакана с Bybit.

    DataProvider: реализация интерфейса DataProvider для Bybit.
    Поддерживает spot и linear perpetual через параметр market_type.

    Bybit v5 — depth200, обновление каждые 100ms.
    """

    def __init__(self, pairs: list[str], market_type: str = "spot"):
        super().__init__(pairs)
        self._ws: Optional[aiohttp.ClientWebSocketResponse] = None
        self._reconnect_delay = 1.0
        self._market_type = market_type  # "spot" или "linear"

    @property
    def name(self) -> str:
        return "bybit"

    @property
    def _ws_url(self) -> str:
        return BYBIT_WS_SPOT if self._market_type == "spot" else BYBIT_WS_LINEAR

    def _topic_for_pair(self, pair: str) -> str:
        """Генерирует topic name для пары на Bybit."""
        return ORDERBOOK_TOPIC_TEMPLATE.format(symbol=pair.upper())

    async def start(
        self,
        callback: Callable[[OrderBookSnapshot],
                           Coroutine[Any, Any, None]],
    ) -> None:
        """Запустить WS и слушать до остановки.

        DataProvider: реализация абстрактного метода start().
        Bybit: subscribe → listen → reconnect.
        """
        self._callback = callback
        self._running = True

        if not self._pairs:
            logger.error("[BybitDataProvider] No pairs configured, cannot start")
            return

        while self._running:
            try:
                await self._connect_and_subscribe()
            except Exception as e:
                if not self._running:
                    break
                logger.warning(
                    f"[BybitDataProvider] Error: {e}. "
                    f"Reconnect in {self._reconnect_delay}s..."
                )
                await asyncio.sleep(self._reconnect_delay)
                self._reconnect_delay = min(self._reconnect_delay * 2, 60.0)

    async def _connect_and_subscribe(self):
        """Подключиться, подписаться и слушать поток.

        Bybit требует подписки после коннекта:
          1. Connect
          2. Send subscribe message
          3. Listen for messages
        """
        topics = [self._topic_for_pair(p) for p in self._pairs]

        if not topics:
            raise ValueError("No pairs configured for Bybit stream")

        logger.info(
            f"[BybitDataProvider] Connecting to {self._ws_url} "
            f"({len(topics)} topic(s))"
        )

        async with aiohttp.ClientSession(
            timeout=aiohttp.ClientTimeout(total=30)
        ) as session:
            try:
                async with session.ws_connect(
                    self._ws_url,
                    heartbeat=30.0,
                    max_msg_size=2 * 1024 * 1024,
                ) as ws:
                    self._ws = ws
                    self._reconnect_delay = 1.0
                    logger.info(
                        f"[BybitDataProvider] Connected to {self._ws_url}"
                    )

                    # Subscribe to topics
                    subscribe_msg = {
                        "op": "subscribe",
                        "args": topics,
                    }
                    await ws.send_json(subscribe_msg)
                    logger.info(
                        f"[BybitDataProvider] Subscribed to {len(topics)} topic(s)"
                    )

                    # Listen for messages
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
                logger.warning(
                    "[BybitDataProvider] WS connection timeout, will reconnect"
                )
                raise
            except Exception as e:
                logger.warning(
                    f"[BybitDataProvider] WS connection error: {e}"
                )
                raise

    async def _on_message(self, raw: str):
        """Парсинг сообщения Bybit -> OrderBookSnapshot.

        Bybit v5 orderbook snapshot:
          {
            "topic": "orderbook.200.100ms.BTCUSDT",
            "type": "snapshot",
            "ts": 1234567890123,
            "data": {
              "s": "BTCUSDT",
              "b": [["price","qty"],...],  // sorted desc
              "a": [["price","qty"],...],  // sorted asc
              "u": 123456,
              "seq": 789012
            }
          }

        Delta update:
          {"type": "delta", "data": {"s":"BTCUSDT","b":[["price","qty",...]], ...}}
        """
        try:
            msg = json.loads(raw)

            # Handle subscription response (op: subscribe)
            if msg.get("op") == "subscribe":
                success = msg.get("success", False)
                if not success:
                    logger.warning(
                        f"[BybitDataProvider] Subscribe failed: "
                        f"{msg.get('ret_msg', 'unknown')}"
                    )
                return

            # Extract data
            topic = msg.get("topic", "")
            msg_type = msg.get("type", "")  # "snapshot" or "delta"
            data = msg.get("data", msg)

            pair = data.get("s", "")
            if not pair:
                # Extract from topic: orderbook.200.100ms.BTCUSDT -> BTCUSDT
                parts = topic.split(".")
                if len(parts) >= 4:
                    pair = parts[-1]

            bids_raw = data.get("b", [])
            asks_raw = data.get("a", [])

            if not pair or not bids_raw or not asks_raw:
                return

            bids = [(float(p), float(q)) for p, q in bids_raw if float(q) > 0]
            asks = [(float(p), float(q)) for p, q in asks_raw if float(q) > 0]

            if not bids or not asks:
                return

            snap = OrderBookSnapshot(
                pair=pair,
                timestamp=datetime.now(timezone.utc),
                bids=bids,
                asks=asks,
            )
            if self._callback:
                await self._callback(snap)
        except (json.JSONDecodeError, KeyError, ValueError, TypeError) as e:
            logger.debug(f"[BybitDataProvider] Parse error: {e}")

    async def stop(self):
        """DataProvider: остановить получение данных."""
        self._running = False
        if self._ws and not self._ws.closed:
            await self._ws.close()
        logger.info("[BybitDataProvider] Stopped")
