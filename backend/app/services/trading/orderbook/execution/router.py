"""DataExchangeRouter — связывает источник данных и биржу исполнения.

Архитектура:
  DataProvider (WS данные) → OrderBookEngine → ExchangeExecutor (ордера)

  source_exchange: откуда данные (binance, bybit, ...)
  trade_exchange:   где торгуем     (binance, bybit, ...)

Пользователь может комбинировать:
  - Binane → Binance  (одна биржа)
  - Binance → Bybit    (данные с Binance, торгуем на Bybit)
  - Bybit → Bybit
  - Bybit → Binance
  - и т.д.
"""
from __future__ import annotations

import logging
from typing import Optional

from app.services.trading.exchange.base import AbstractExchange
from app.services.trading.orderbook.data import DataProvider, DataProviderFactory

logger = logging.getLogger(__name__)

# Registry: exchange name -> exchange class (для исполнения)
EXECUTION_REGISTRY: dict[str, str] = {
    "binance": "BinanceExchange",
    "bybit": "BybitExchange",
}


class ExchangeExecutor:
    """Обёртка над AbstractExchange для OB-движка.

    Создаёт и кэширует экземпляр AbstractExchange по имени биржи.
    Проксирует вызовы place_order(), get_balance(), get_ticker().
    """

    def __init__(self, trade_exchange: str):
        self._trade_exchange = trade_exchange
        self._exchange: Optional[AbstractExchange] = None

    async def get_exchange(self) -> AbstractExchange:
        """Ленивое создание AbstractExchange."""
        if self._exchange is not None:
            return self._exchange

        exchange_class_name = EXECUTION_REGISTRY.get(self._trade_exchange)
        if exchange_class_name is None:
            raise ValueError(
                f"Unsupported execution exchange: '{self._trade_exchange}'. "
                f"Available: {list(EXECUTION_REGISTRY.keys())}"
            )

        # Import динамически
        import importlib

        module = importlib.import_module(
            f"app.services.trading.exchange.{self._trade_exchange}"
        )
        exchange_cls = getattr(module, exchange_class_name)

        self._exchange = exchange_cls()
        exchange: AbstractExchange = self._exchange  # type: ignore
        logger.info(
            f"[ExchangeExecutor] Created {exchange_class_name} "
            f"for trade exchange: {self._trade_exchange}"
        )
        return exchange

    async def place_order(
        self, pair: str, side: str, quantity: float,
        order_type: str = "market", price: Optional[float] = None,
    ) -> dict:
        """Разместить ордер на бирже торговли."""
        ex = await self.get_exchange()
        return await ex.place_order(
            pair, side, quantity,
            order_type=order_type, price=price,
        )

    async def get_balance(self, currency: str = "") -> dict:
        """Получить баланс с биржи торговли."""
        ex = await self.get_exchange()
        return await ex.get_balance(currency)

    async def get_ticker(self, pair: str) -> dict:
        """Получить текущий тикер с биржи торговли."""
        ex = await self.get_exchange()
        return await ex.get_ticker(pair)

    @property
    def trade_exchange(self) -> str:
        return self._trade_exchange


class DataExchangeRouter:
    """Связывает DataProvider (источник данных) и ExchangeExecutor (исполнение).

    Использование:
        router = DataExchangeRouter(source_exchange, trade_exchange, pairs)
        provider = router.data_provider
        executor = router.executor

        await provider.start(engine._on_snapshot)
        await executor.place_order("BTCUSDT", "BUY", 0.001)
    """

    def __init__(
        self,
        source_exchange: str = "binance",
        trade_exchange: str = "binance",
        pairs: Optional[list[str]] = None,
    ):
        self.source_exchange = source_exchange
        self.trade_exchange = trade_exchange
        self._pairs = pairs or ["BTCUSDT"]

        # Создаём DataProvider
        self.data_provider: DataProvider = DataProviderFactory.create(
            exchange=source_exchange,
            pairs=self._pairs,
        )

        # Создаём ExchangeExecutor для торговли
        self.executor: ExchangeExecutor = ExchangeExecutor(
            trade_exchange=trade_exchange,
        )

        logger.info(
            f"[DataExchangeRouter] Data: {source_exchange} → Trade: {trade_exchange} "
            f"for {len(self._pairs)} pair(s)"
        )

    def __repr__(self) -> str:
        return (
            f"DataExchangeRouter(data={self.source_exchange}, "
            f"trade={self.trade_exchange}, pairs={self._pairs})"
        )

    async def validate_connection(self) -> dict:
        """Проверить что оба компонента работают.

        Returns:
            dict со статусом каждого компонента.
        """
        result = {
            "data_provider": {"exchange": self.source_exchange, "status": "ok"},
            "executor": {"exchange": self.trade_exchange, "status": "ok"},
        }

        # Проверка DataProvider
        if not self.data_provider.pairs:
            result["data_provider"]["status"] = "error"
            result["data_provider"]["error"] = "No pairs configured"

        # Проверка ExchangeExecutor
        try:
            await self.executor.get_exchange()
        except ValueError as e:
            result["executor"]["status"] = "error"
            result["executor"]["error"] = str(e)

        return result

    async def close(self):
        """Закрыть все соединения."""
        await self.data_provider.stop()
