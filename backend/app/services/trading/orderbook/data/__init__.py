"""Data providers — абстракция источника данных стакана.

Каждый провайдер:
- Получает данные с конкретной биржи (WS или REST)
- Нормализует их в OrderBookSnapshot
- Передаёт в callback

DataProviderFactory — создаёт провайдера по имени биржи.
"""

from app.services.trading.orderbook.data.base import DataProvider
from app.services.trading.orderbook.data.factory import (
    DataProviderFactory,
    list_providers,
)
from app.services.trading.orderbook.data.binance_provider import (
    BinanceDataProvider,
)
from app.services.trading.orderbook.data.bybit_provider import (
    BybitDataProvider,
)

__all__ = [
    "DataProvider",
    "DataProviderFactory",
    "BinanceDataProvider",
    "BybitDataProvider",
    "list_providers",
]
