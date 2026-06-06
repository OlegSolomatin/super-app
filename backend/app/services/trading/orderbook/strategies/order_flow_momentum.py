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

_BURST_RESET_TICKS = 5  # сброс счётчика burst если столько тиков без активности


class OrderFlowMomentumStrategy(AbstractOrderBookStrategy):
    """Стратегия торговли по потоку агрессивных ордеров."""

    name = "order_flow_momentum"

    def __init__(self, config: OrderBookConfig):
        super().__init__(config)
        self._buy_burst_count: int = 0
        self._sell_burst_count: int = 0
        self._buy_tick_since_burst: int = 0
        self._sell_tick_since_burst: int = 0

    def analyze(self, snap: OrderBookSnapshot,
                cache: OrderBookCache) -> Optional[OrderBookSignal]:
        c = self.config

        # Защита: спред
        if snap.spread_pct > c.max_spread_pct:
            self._reject(f"spread={snap.spread_pct:.4f} > {c.max_spread_pct}")
            return None

        window = cache.window(10)
        if len(window) < 5:
            self._reject(f"window={len(window)} < 5")
            return None

        top_bid_vol = snap.bids[0][1] if snap.bids else 0.0
        top_ask_vol = snap.asks[0][1] if snap.asks else 0.0
        best_ask_price = snap.ask_price
        best_bid_price = snap.bid_price

        # Сравниваем с предыдущим тиком
        prev = window[-2] if len(window) >= 2 else None
        if prev is None:
            self._reject("no_prev_tick")
            return None

        prev_top_bid = prev.bids[0][1] if prev.bids else 0.0
        prev_top_ask = prev.asks[0][1] if prev.asks else 0.0

        # Market buy = ask объём на лучшей цене резко упал
        ask_vol_consumed = prev_top_ask - top_ask_vol
        has_buy_burst = (
            ask_vol_consumed > c.flow_threshold_volume
            and best_ask_price > best_bid_price
        )

        # Market sell = bid объём на лучшей цене резко упал
        bid_vol_consumed = prev_top_bid - top_bid_vol
        has_sell_burst = (
            bid_vol_consumed > c.flow_threshold_volume
            and best_ask_price > best_bid_price
        )

        # Buy burst: счётчик + таймер
        if has_buy_burst:
            self._buy_burst_count += 1
            self._buy_tick_since_burst = 0
        else:
            self._buy_tick_since_burst += 1
            if self._buy_tick_since_burst > _BURST_RESET_TICKS:
                self._buy_burst_count = 0

        # Sell burst: счётчик + таймер
        if has_sell_burst:
            self._sell_burst_count += 1
            self._sell_tick_since_burst = 0
        else:
            self._sell_tick_since_burst += 1
            if self._sell_tick_since_burst > _BURST_RESET_TICKS:
                self._sell_burst_count = 0

        # Сигнал BUY: N buy bursts подряд
        if has_buy_burst and self._buy_burst_count >= c.min_flow_signals:
            burst_count = self._buy_burst_count
            self._buy_burst_count = 0
            return OrderBookSignal(
                pair=snap.pair,
                side="BUY",
                price=snap.ask_price,
                strategy_name=self.name,
                confidence=min(ask_vol_consumed / c.flow_threshold_volume, 0.95),
                reason=(
                    f"ask_flow={ask_vol_consumed:.0f} "
                    f"bursts={burst_count}"
                ),
                exit_after_seconds=c.flow_exit_seconds,
                entry_tag="flow_momentum_buy",
            )

        # Сигнал SELL: N sell bursts подряд
        if has_sell_burst and self._sell_burst_count >= c.min_flow_signals:
            burst_count = self._sell_burst_count
            self._sell_burst_count = 0
            return OrderBookSignal(
                pair=snap.pair,
                side="SELL",
                price=snap.bid_price,
                strategy_name=self.name,
                confidence=min(bid_vol_consumed / c.flow_threshold_volume, 0.95),
                reason=(
                    f"bid_flow={bid_vol_consumed:.0f} "
                    f"bursts={burst_count}"
                ),
                exit_after_seconds=c.flow_exit_seconds,
                entry_tag="flow_momentum_sell",
            )

        # Недостаточно burst'ов для сигнала
        self._reject(
            f"no_burst: buy={self._buy_burst_count}/{c.min_flow_signals} "
            f"sell={self._sell_burst_count}/{c.min_flow_signals} "
            f"ask_vol={ask_vol_consumed:.0f} "
            f"bid_vol={bid_vol_consumed:.0f}"
        )
        return None

    def custom_exit(self, trade: Trade, snap: OrderBookSnapshot,
                    cache: OrderBookCache) -> Optional[str]:
        """Выход при затухании потока."""
        window = cache.window(10)
        if len(window) < 5:
            return None

        recent = window[-5:]
        bursts_found = 0
        for i in range(1, len(recent)):
            prev = recent[i - 1]
            curr = recent[i]
            pask = prev.asks[0][1] if prev.asks else 0.0
            pbid = prev.bids[0][1] if prev.bids else 0.0
            cask = curr.asks[0][1] if curr.asks else 0.0
            cbid = curr.bids[0][1] if curr.bids else 0.0

            if trade.side == "BUY":
                if (pask - cask) > self.config.flow_threshold_volume:
                    bursts_found += 1
            else:
                if (pbid - cbid) > self.config.flow_threshold_volume:
                    bursts_found += 1

        if bursts_found == 0:
            return "flow_dried_up"
        return None
