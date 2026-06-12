"""Фабрика провайдеров данных стакана.

Создаёт DataProvider по имени биржи.
При добавлении новой биржи:
  1. Создать XXXDataProvider(DataProvider)
  2. Добавить в PROVIDER_REGISTRY

ccxt: ccxt.Exchange().watch_order_book() — единый интерфейс для всех бирж,
но мы используем прямые WS для лучшего контроля.
"""
from __future__ import annotations

import logging
from typing import Optional

from app.services.trading.orderbook.data.base import DataProvider
from app.services.trading.orderbook.data.binance_provider import (
    BinanceDataProvider,
)
from app.services.trading.orderbook.data.bybit_provider import (
    BybitDataProvider,
)

logger = logging.getLogger(__name__)

# Registry: name -> (class, kwargs)
PROVIDER_REGISTRY: dict[str, tuple[type[DataProvider], dict]] = {
    "binance": (BinanceDataProvider, {}),
    "bybit": (BybitDataProvider, {"market_type": "spot"}),
    "bybit_linear": (BybitDataProvider, {"market_type": "linear"}),
}


def list_providers() -> list[str]:
    """Список доступных провайдеров."""
    return sorted(PROVIDER_REGISTRY.keys())


class DataProviderFactory:
    """Фабрика: создаёт DataProvider по имени биржи.

    Использование:
        provider = DataProviderFactory.create("binance", pairs=["BTCUSDT"])
        provider = DataProviderFactory.create("bybit", pairs=["BTCUSDT"])
    """

    @staticmethod
    def create(
        exchange: str,
        pairs: list[str],
    ) -> DataProvider:
        """Создать DataProvider.

        Args:
            exchange: Имя биржи (binance, bybit, bybit_linear).
            pairs: Список пар в формате BTCUSDT.

        Returns:
            DataProvider для указанной биржи.

        Raises:
            ValueError: Если биржа не поддерживается.
        """
        exchange = exchange.lower().strip()

        entry = PROVIDER_REGISTRY.get(exchange)
        if entry is None:
            raise ValueError(
                f"Unsupported data provider: '{exchange}'. "
                f"Available: {list_providers()}"
            )

        provider_cls, extra_kwargs = entry

        instance = provider_cls(pairs, **extra_kwargs)

        logger.info(
            f"[DataProviderFactory] Created {instance.name} "
            f"provider for {len(pairs)} pair(s)"
        )
        return instance
