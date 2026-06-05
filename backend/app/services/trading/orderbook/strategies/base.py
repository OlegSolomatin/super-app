"""Базовый класс для Order Book стратегий.

freqtrade: IStrategy (interface.py) — ~40 атрибутов + 20 коллбэков.
Адаптировано под стакан.
"""
from __future__ import annotations

from abc import ABC, abstractmethod
from typing import Optional

from app.services.trading.orderbook.models import (
    OrderBookCache,
    OrderBookConfig,
    OrderBookSignal,
    OrderBookSnapshot,
    Trade,
)


class AbstractOrderBookStrategy(ABC):
    """Базовый класс стратегии торговли по стакану.

    Обязательный метод: analyze().
    Опциональные: confirm_trade_entry(), custom_exit().
    """

    name: str = ""

    def __init__(self, config: OrderBookConfig):
        self.config = config

    @abstractmethod
    def analyze(self, snap: OrderBookSnapshot,
                cache: OrderBookCache) -> Optional[OrderBookSignal]:
        """Оценить текущий тик стакана.

        freqtrade: populate_indicators() + populate_entry_trend()
        Вызывается на каждый снапшот (~100ms).
        """
        ...

    def confirm_trade_entry(self, signal: OrderBookSignal) -> bool:
        """Gatekeeper: подтвердить вход перед исполнением.

        freqtrade: IStrategy.confirm_trade_entry()
        """
        return True

    def custom_exit(self, trade: Trade, snap: OrderBookSnapshot,
                    cache: OrderBookCache) -> Optional[str]:
        """Кастомный сигнал выхода.

        freqtrade: IStrategy.custom_exit()
        """
        return None

    def custom_stoploss(self, trade: Trade,
                        current_price: float) -> float:
        """Динамический стоп-лосс. Не может превысить config.stoploss.

        freqtrade: IStrategy.custom_stoploss()
        """
        return self.config.stoploss

    def custom_stake_amount(self, proposed_stake: float,
                            free_balance: float) -> float:
        return proposed_stake

    # ── Helpers (общие для всех стратегий) ───────────────────────────

    _ICEBERG_RATIO: float = 5.0  # порог для детекции iceberg ордеров

    def is_iceberg(self, snap: "OrderBookSnapshot") -> bool:
        """Проверить, есть ли iceberg-ордер в стакане."""
        if len(snap.bids) >= 2:
            top_bid_qty = snap.bids[0][1]
            next_bid_qty = snap.bids[1][1]
            if top_bid_qty > next_bid_qty * self._ICEBERG_RATIO and next_bid_qty > 0:
                return True
        if len(snap.asks) >= 2:
            top_ask_qty = snap.asks[0][1]
            next_ask_qty = snap.asks[1][1]
            if top_ask_qty > next_ask_qty * self._ICEBERG_RATIO and next_ask_qty > 0:
                return True
        return False
