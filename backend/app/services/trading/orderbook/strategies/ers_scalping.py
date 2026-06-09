"""Strategy 4: ЕРШ Scalping — ultra-fast tick scalping.

ЕРШ = «Единый Рыночный Шанс» — сверхкраткосрочный скальпинг.

Идея:
  Вход на ЛЮБОМ detectable дисбалансе стакана (0.50+).
  Выход при микро-профите (0.01%) или реверсии цены к entry.
  Без подтверждения, без ожидания — чистая скорость.

freqtrade: IStrategy (interface.py)
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


class ErsScalpingStrategy(AbstractOrderBookStrategy):
    """Стратегия 4: ЕРШ Scalping — сверхчувствительный скальпинг."""

    name = "ers_scalping"

    def __init__(self, config: OrderBookConfig):
        super().__init__(config)

    def analyze(self, snap: OrderBookSnapshot,
                cache: OrderBookCache) -> Optional[OrderBookSignal]:
        """Вход на ЛЮБОМ detectable дисбалансе стакана.

        Условия:
          1. spread < max_spread_pct
          2. imbalance > ers_min_imbalance (BUY) или < 1-ers_min_imbalance (SELL)
          3. объём на топе > ers_min_volume (если задан)
          4. Без подтверждения — сразу сигнал
        """
        c = self.config

        # 1. Защита: спред
        if snap.spread_pct > c.max_spread_pct:
            self._reject(f"spread={snap.spread_pct:.4f}>{c.max_spread_pct}")
            return None

        imb = snap.imbalance
        min_imb = c.ers_min_imbalance

        # Флаг микро-объёма на топе книги
        bid_top = snap.bids[0][1] if snap.bids else 0.0
        ask_top = snap.asks[0][1] if snap.asks else 0.0
        min_vol = c.ers_min_volume

        # BUY — bids доминируют
        if imb >= min_imb and bid_top >= min_vol:
            conf = min((imb - 0.5) * 2, 0.95)  # 0.50→0.0, 0.95→0.9
            return OrderBookSignal(
                pair=snap.pair,
                side="BUY",
                price=snap.ask_price,
                strategy_name=self.name,
                confidence=round(conf, 2),
                reason=f"ers_buy imb={imb:.3f} vol={bid_top:.2f}",
                exit_after_seconds=c.ers_max_hold_seconds,
                entry_tag="ers_buy",
            )

        # SELL — asks доминируют
        if (1 - imb) >= min_imb and ask_top >= min_vol:
            conf = min((1 - imb - 0.5) * 2, 0.95)
            return OrderBookSignal(
                pair=snap.pair,
                side="SELL",
                price=snap.bid_price,
                strategy_name=self.name,
                confidence=round(conf, 2),
                reason=f"ers_sell imb={1-imb:.3f} vol={ask_top:.2f}",
                exit_after_seconds=c.ers_max_hold_seconds,
                entry_tag="ers_sell",
            )

        self._reject(
            f"no_pattern: imb={imb:.3f} "
            f"bid_top={bid_top:.2f} ask_top={ask_top:.2f}"
        )
        return None

    def custom_exit(self, trade: Trade, snap: OrderBookSnapshot,
                    cache: OrderBookCache) -> Optional[str]:
        """Кастомный выход для ЕРШ.

        Приоритет (каждые 500ms):
          1. Микро-профит — exit при +ers_min_profit_pct%
          2. Реверсия — цена вернулась к entry (опционально)
          3. Max hold — аварийный (уже в manage_loop)
        """
        c = self.config

        profit = trade.current_profit(snap.mid_price)

        # 1. Микро-профит
        if profit >= c.ers_min_profit_pct:
            return f"micro_profit_{profit:.4f}%"

        # 2. Реверсия — цена вернулась к entry
        if c.ers_exit_on_reversion:
            price_diff = (
                abs(snap.mid_price - trade.entry_price)
                / trade.entry_price * 100
            )
            # Если разница < 0.005% от entry — считаем что реверсия
            if price_diff < 0.005:
                return "price_reverted"

        return None
