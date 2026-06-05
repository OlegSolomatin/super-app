"""Strategy 3: Order Flow Momentum.

Торговля по агрессивным market orders:
- BUY когда крупные market buy (агрессивный покупатель бьёт в ask)
- SELL когда крупные market sell (агрессивный продавец бьёт в bid)

Логика:
1. Отслеживаем резкие изменения объёмов на лучших ценах
2. Если ask объём на лучшей цене резко упал = market buy сожрал ask → сигнал BUY
3. Если bid объём на лучшей цене резко упал = market sell сожрал bid → сигнал SELL
4. Требуем N подтверждений подряд за окно
"""
from __future__ import annotations

from typing import Optional

from app.services.trading.orderbook.models import (
    OrderBookCache,
    OrderBookConfig,
    OrderBookSignal,
    OrderBookSnapshot,
    Trade,
)
from app.services.trading.orderbook.strategies.base import (
    AbstractOrderBookStrategy,
)


class OrderFlowMomentumStrategy(AbstractOrderBookStrategy):
    """Стратегия торговли по потоку агрессивных ордеров."""

    name = "order_flow_momentum"

    def __init__(self, config: OrderBookConfig):
        super().__init__(config)
        self._flow_bursts_buy: int = 0
        self._flow_bursts_sell: int = 0
        self._last_burst_tick: int = 0

    def analyze(self, snap: OrderBookSnapshot,
                cache: OrderBookCache) -> Optional[OrderBookSignal]:
        c = self.config

        # Защита: спред
        if snap.spread_pct > c.max_spread_pct:
            return None

        window = cache.window(10)
        if len(window) < 5:
            return None

        # Определяем агрессивные объёмы
        top_bid_vol = snap.bids[0][1] if snap.bids else 0.0
        top_ask_vol = snap.asks[0][1] if snap.asks else 0.0
        best_bid_price = snap.bid_price
        best_ask_price = snap.ask_price

        # Сравниваем с предыдущим тиком
        prev = window[-2] if len(window) >= 2 else None
        if prev is None:
            return None

        prev_top_bid = prev.bids[0][1] if prev.bids else 0.0
        prev_top_ask = prev.asks[0][1] if prev.asks else 0.0

        # Market buy detected: ask объём на лучшей цене резко упал
        # (агрессивный покупатель снёс ликвидность на ask)
        bid_drop = prev_top_ask - top_ask_vol
        has_buy_burst = (
            bid_drop > c.flow_threshold_volume
            and best_ask_price > best_bid_price  # рынок не перевёрнут
        )

        # Market sell detected: bid объём на лучшей цене резко упал
        ask_drop = prev_top_bid - top_bid_vol
        has_sell_burst = (
            ask_drop > c.flow_threshold_volume
            and best_ask_price > best_bid_price
        )

        # Счётчик тиков
        self._last_burst_tick += 1

        if has_buy_burst:
            self._flow_bursts_buy += 1
            self._last_burst_tick = 0
        else:
            # Сбрасываем счётчик если давно не было burst
            if self._last_burst_tick > 5:
                self._flow_bursts_buy = 0

        if has_sell_burst:
            self._flow_bursts_sell += 1
            self._last_burst_tick = 0
        else:
            if self._last_burst_tick > 5:
                self._flow_bursts_sell = 0

        # Сигнал BUY: N buy bursts подряд
        if has_buy_burst and self._flow_bursts_buy >= c.min_flow_signals:
            self._flow_bursts_buy = 0  # сброс после сигнала
            return OrderBookSignal(
                pair=snap.pair,
                side="BUY",
                price=snap.ask_price,
                strategy_name=self.name,
                confidence=min(bid_drop / c.flow_threshold_volume, 0.95),
                reason=(
                    f"buy_flow={bid_drop:.0f} "
                    f"bursts={self._flow_bursts_buy + 1}"
                ),
                exit_after_seconds=c.flow_exit_seconds,
                entry_tag="flow_momentum_buy",
            )

        # Сигнал SELL: N sell bursts подряд
        if has_sell_burst and self._flow_bursts_sell >= c.min_flow_signals:
            self._flow_bursts_sell = 0  # сброс после сигнала
            return OrderBookSignal(
                pair=snap.pair,
                side="SELL",
                price=snap.bid_price,
                strategy_name=self.name,
                confidence=min(ask_drop / c.flow_threshold_volume, 0.95),
                reason=(
                    f"sell_flow={ask_drop:.0f} "
                    f"bursts={self._flow_bursts_sell + 1}"
                ),
                exit_after_seconds=c.flow_exit_seconds,
                entry_tag="flow_momentum_sell",
            )

        return None

    def custom_exit(self, trade: Trade, snap: OrderBookSnapshot,
                    cache: OrderBookCache) -> Optional[str]:
        """Выход при затухании потока."""
        window = cache.window(10)
        if len(window) < 5:
            return None

        # Проверяем последние 5 тиков — был ли хоть один burst
        recent = window[-5:]
        bursts_found = 0
        for i in range(1, len(recent)):
            prev = recent[i - 1]
            curr = recent[i]
            pbid = prev.bids[0][1] if prev.bids else 0.0
            pask = prev.asks[0][1] if prev.asks else 0.0
            cbid = curr.bids[0][1] if curr.bids else 0.0
            cask = curr.asks[0][1] if curr.asks else 0.0

            if trade.side == "BUY":
                if (pask - cask) > self.config.flow_threshold_volume:
                    bursts_found += 1
            else:
                if (pbid - cbid) > self.config.flow_threshold_volume:
                    bursts_found += 1

        # Если за последние 5 тиков нет burst — поток затух
        if bursts_found == 0:
            return "flow_dried_up"
        return None
