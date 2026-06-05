"""Strategy 2: Spread Capture (Market Making Lite).

Торговля по спреду:
- BUY когда спред существенно расширился (ожидание сужения)
- SELL когда спред резко сузился (ожидание расширения)

Логика:
1. Рассчитываем baseline спреда (скользящее среднее за N тиков)
2. Если текущий спред > baseline + entry_threshold → BUY (спред расширился)
3. Если текущий спред < baseline - entry_threshold → SELL (спред сузился)
4. Выход: спред вернулся к baseline (exit_threshold) или max hold
"""
from __future__ import annotations

from statistics import mean
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


class SpreadCaptureStrategy(AbstractOrderBookStrategy):
    """Стратегия торговли на расширение/сужение спреда."""

    name = "spread_capture"

    def __init__(self, config: OrderBookConfig):
        super().__init__(config)

    def _baseline_spread(self, window: list[OrderBookSnapshot]) -> float:
        """Средний спред за окно."""
        if not window:
            return 0.0
        return mean(s.spread_pct for s in window)

    def analyze(self, snap: OrderBookSnapshot,
                cache: OrderBookCache) -> Optional[OrderBookSignal]:
        c = self.config

        # Защита: слишком широкий спред
        if snap.spread_pct > c.max_spread_pct:
            return None

        # Защита: слишком узкий спред (неликвид)
        if snap.spread_pct < c.min_spread_pct:
            return None

        # Защита: iceberg
        if self.is_iceberg(snap):
            return None

        window = cache.window(c.spread_baseline_window)
        if len(window) < c.spread_baseline_window // 2:
            return None

        baseline = self._baseline_spread(window)
        deviation = snap.spread_pct - baseline

        # BUY: спред расширился
        if deviation > c.spread_entry_threshold:
            return OrderBookSignal(
                pair=snap.pair,
                side="BUY",
                price=snap.ask_price,
                strategy_name=self.name,
                confidence=min(abs(deviation) / c.spread_entry_threshold, 0.95),
                reason=(
                    f"spread={snap.spread_pct:.4f}% "
                    f"baseline={baseline:.4f}% "
                    f"dev={deviation:.4f}%"
                ),
                exit_after_seconds=c.exit_after_seconds,
                entry_tag="spread_widened",
            )

        # SELL: спред сузился
        if deviation < -c.spread_entry_threshold:
            return OrderBookSignal(
                pair=snap.pair,
                side="SELL",
                price=snap.bid_price,
                strategy_name=self.name,
                confidence=min(abs(deviation) / c.spread_entry_threshold, 0.95),
                reason=(
                    f"spread={snap.spread_pct:.4f}% "
                    f"baseline={baseline:.4f}% "
                    f"dev={deviation:.4f}%"
                ),
                exit_after_seconds=c.exit_after_seconds,
                entry_tag="spread_narrowed",
            )

        return None

    def custom_exit(self, trade: Trade, snap: OrderBookSnapshot,
                    cache: OrderBookCache) -> Optional[str]:
        """Выход при нормализации спреда."""
        c = self.config
        window = cache.window(c.spread_baseline_window)
        if len(window) < c.spread_baseline_window // 2:
            return None
        baseline = self._baseline_spread(window)
        deviation = snap.spread_pct - baseline

        if trade.side == "BUY" and abs(deviation) < c.spread_exit_threshold:
            return "spread_normalized"
        if trade.side == "SELL" and abs(deviation) < c.spread_exit_threshold:
            return "spread_normalized"
        return None
