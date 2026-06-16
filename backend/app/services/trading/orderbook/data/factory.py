"""Data provider factory — creates DataProvider by exchange name.

Supports:
  - binance → BinanceDataProvider (WS depth stream)
  - bybit → BybitDataProvider (WS depth stream)
  - any other → RestOrderBookProvider (REST polling via CCXTExchange)
"""

from __future__ import annotations

import logging
from typing import TYPE_CHECKING

from app.services.trading.orderbook.data.base import DataProvider
from app.services.trading.orderbook.data.binance_provider import (
    BinanceDataProvider,
)
from app.services.trading.orderbook.data.bybit_provider import (
    BybitDataProvider,
)
from app.services.trading.orderbook.data.rest_provider import (
    RestOrderBookProvider,
)
from app.services.trading.orderbook.data.ccxt_ws_provider import (
    CCXTWSProvider,
)

if TYPE_CHECKING:
    from app.services.trading.exchange.base import AbstractExchange

logger = logging.getLogger(__name__)


def list_providers() -> list[str]:
    """List available data provider types."""
    return ["binance", "bybit", "ccxt_ws", "rest"]


class DataProviderFactory:
    """Creates a DataProvider for any exchange.

    Returns WS-based providers for Binance and Bybit, and a REST-polling
    provider for all other exchanges (via CCXTExchange).
    """

    @staticmethod
    def create(
        exchange: str,
        pairs: list[str],
    ) -> DataProvider:
        """Create a DataProvider for the given exchange.

        Args:
            exchange: Exchange name (binance, bybit, mexc, gate, etc.)
            pairs: List of trading pairs to subscribe to.

        Returns:
            DataProvider ready to start().

        Raises:
            ValueError: If exchange is empty or unsupported.
        """
        name = exchange.lower()

        if name == "binance":
            from app.services.trading.orderbook.data.binance_provider import (
                BinanceDataProvider,
            )
            logger.info("[DataFactory] Using native WS provider for %s", name)
            return BinanceDataProvider(pairs=pairs)

        if name == "bybit":
            from app.services.trading.orderbook.data.bybit_provider import (
                BybitDataProvider,
            )
            logger.info("[DataFactory] Using native WS provider for %s", name)
            return BybitDataProvider(pairs=pairs)

        # All other exchanges: try WS via ccxt.pro, fall back to REST
        try:
            import ccxt.pro as ccxt_pro
            exchange_class = getattr(ccxt_pro, name, None)
            if exchange_class is not None:
                # Quick check: does this exchange support watchOrderBook?
                # Creating a lightweight instance to check capabilities
                test_ex = exchange_class({"enableRateLimit": False})
                if test_ex.has.get("watchOrderBook", False):
                    logger.info(
                        "[DataFactory] Using CCXT WS provider for %s (%d pairs)",
                        name, len(pairs),
                    )
                    return CCXTWSProvider(
                        pairs=pairs,
                        exchange_name=name,
                    )
        except Exception as e:
            logger.warning(
                "[DataFactory] WS check failed for %s: %s. Falling back to REST.",
                name, e,
            )

        # Fallback: REST polling via CCXT
        from app.services.trading.exchange.ccxt_exchange import CCXTExchange
        exchange_instance = CCXTExchange(exchange_name=name)
        logger.info(
            "[DataFactory] Using REST provider for %s (%d pairs, interval=%.1fs)",
            name, len(pairs), 1.5,
        )
        return RestOrderBookProvider(
            pairs=pairs,
            exchange=exchange_instance,
            poll_interval=1.5,
        )
