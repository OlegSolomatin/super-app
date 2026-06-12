"""Абстрактный базовый класс DataProvider.

Каждый провайдер данных стакана должен наследовать этот класс
и реализовать start/stop.

freqtrade: DataHandler — generic data interface.
ccxt: client.watch() + order_book() — единый интерфейс для всех WS.
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from asyncio import iscoroutinefunction
from typing import Any, Callable, Coroutine, Optional

from app.services.trading.orderbook.models import OrderBookSnapshot


class DataProvider(ABC):
    """Базовый класс для провайдеров данных стакана.

    Свойства:
        name: Имя биржи (binance, bybit, mexc, ...)
        pairs: Список пар, за которыми следим

    Методы:
        start(callback): Запустить поток данных.
            callback — асинхронная функция, вызывается на каждый снапшот.
        stop(): Остановить поток данных.
    """

    def __init__(self, pairs: list[str]):
        self._pairs = pairs
        self._callback: Optional[Callable[[OrderBookSnapshot],
                                          Coroutine[Any, Any, None]]] = None
        self._running = False

    @property
    @abstractmethod
    def name(self) -> str:
        """Имя биржи (binance, bybit, ...)."""
        ...

    @property
    def pairs(self) -> list[str]:
        return list(self._pairs)

    @abstractmethod
    async def start(
        self,
        callback: Callable[[OrderBookSnapshot],
                           Coroutine[Any, Any, None]],
    ) -> None:
        """Запустить получение данных.

        Блокирует выполнение (или ожидает в цикле), пока не вызван stop().
        На каждый полученный снапшот вызывает callback.

        ccxt: Client.watch_orders() / Client.watch_order_book()
        """
        self._running = True

    @abstractmethod
    async def stop(self) -> None:
        """Остановить получение данных."""
        self._running = False
