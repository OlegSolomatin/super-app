"""Strategy 1: Imbalance Scalping.

Ловит момент, когда одна сторона стакана резко доминирует.

Сигнал BUY:
  1. imbalance > threshold (0.65)
  2. bid_volume вырос > surge% за 5 тиков
  3. spread < max_spread (0.05%)
  4. 3 тика подряд imbalance > 0.55
  5. Не iceberg

Выход: нормализация дисбаланса или max hold.
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


class ImbalanceScalpingStrategy(AbstractOrderBookStrategy):
    """Стратегия торговли по дисбалансу стакана."""

    name = "imbalance_scalping"

    def __init__(self, config: OrderBookConfig):
        super().__init__(config)

    def analyze(self, snap: OrderBookSnapshot,
                cache: OrderBookCache) -> Optional[OrderBookSignal]:
        c = self.config

        # Защита: спред
        if snap.spread_pct > c.max_spread_pct:
            return None

        # Защита: iceberg
        if self.is_iceberg(snap):
            return None

        window = cache.window(c.confirmation_ticks + 2)
        if len(window) < c.confirmation_ticks:
            return None

        imb = snap.imbalance
        surge_bid = self._volume_surge(window, "bid")
        surge_ask = self._volume_surge(window, "ask")

        # BUY
        if (imb > c.imbalance_threshold
                and surge_bid > c.surge_pct
                and self._confirm_trend(window, 0.55, "bid")):
            return OrderBookSignal(
                pair=snap.pair,
                side="BUY",
                price=snap.ask_price,
                strategy_name=self.name,
                confidence=min(imb, 0.95),
                reason=f"imb={imb:.3f} surge={surge_bid:.1f}%",
                exit_after_seconds=c.exit_after_seconds,
                entry_tag="imbalance_buy",
            )

        # SELL
        if ((1 - imb) > c.imbalance_threshold
                and surge_ask > c.surge_pct
                and self._confirm_trend(window, 0.45, "ask")):
            return OrderBookSignal(
                pair=snap.pair,
                side="SELL",
                price=snap.bid_price,
                strategy_name=self.name,
                confidence=min(1 - imb, 0.95),
                reason=f"imb={imb:.3f} surge={surge_ask:.1f}%",
                exit_after_seconds=c.exit_after_seconds,
                entry_tag="imbalance_sell",
            )

        return None

    def custom_exit(self, trade: Trade, snap: OrderBookSnapshot,
                    cache: OrderBookCache) -> Optional[str]:
        """Выход при нормализации дисбаланса.

        freqtrade: IStrategy.custom_exit()
        """
        imb = snap.imbalance
        if trade.side == "BUY" and imb < 0.55:
            return "imbalance_normalized"
        if trade.side == "SELL" and imb > 0.45:
            return "imbalance_normalized"
        return None

    def _volume_surge(self, window: list, side: str) -> float:
        if len(window) < 2:
            return 0.0
        vol_0 = (window[0].total_bid_volume if side == "bid"
                 else window[0].total_ask_volume)
        vol_n = (window[-1].total_bid_volume if side == "bid"
                 else window[-1].total_ask_volume)
        if vol_0 <= 0:
            return 0.0
        return (vol_n - vol_0) / vol_0 * 100

    def _confirm_trend(self, window: list,
                       threshold: float, side: str) -> bool:
        recent = window[-self.config.confirmation_ticks:]
        if side == "bid":
            for snap in recent:
                if snap.imbalance < threshold:
                    return False
        else:
            for snap in recent:
                if snap.imbalance > (1 - threshold):
                    return False
        return True
