"""Strategy 5: Iceberg Detection.

Обнаруживает скрытые ордера (iceberg) по поведению стакана.
Торгует в сторону найденного iceberg — кто-то крупный
накапливает/распределяет позицию.

Признаки iceberg (из PLAN_ORDER_BOOK_SYSTEM.md Фаза 5):
  1. Аномальный объём: уровень N > уровень N+1 в 3x+
  2. После съедания уровня — цена идёт в направлении iceberg
  3. Общий объём на одной стороне растёт, хотя уровни меняются
  4. Один и тот же объём всплывает на новых уровнях

Сигналы:
  iceberg на bid (накопление) → BUY
  iceberg на ask (распределение) → SELL

freqtrade: нет прямого аналога. Ближе всего: 
  custom_entry_price() + анализ depth of market.
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


class IcebergDetectionStrategy(AbstractOrderBookStrategy):
    """Стратегия 5: Торговля по Iceberg-ордерам.

    Ищет паттерны скрытых ордеров в стакане.
    Торгует только при уверенном обнаружении 3+ тиков подряд.
    """

    name = "iceberg_detection"

    def __init__(self, config: OrderBookConfig):
        super().__init__(config)
        self.iceberg_ratio = getattr(config, "iceberg_ratio", 3.0)
        self.lookback_ticks = getattr(config, "lookback_ticks", 5)
        self.min_volume_btc = getattr(config, "min_volume_btc", 0.5)
        self.confirmation_ticks = getattr(config, "confirmation_ticks", 3)
        self.exit_after_seconds = getattr(config, "exit_after_seconds", 90)
        self.stoploss = getattr(config, "stoploss", -1.0)

    def analyze(self, snap: OrderBookSnapshot,
                cache: OrderBookCache) -> Optional[OrderBookSignal]:
        """Оценить текущий тик на наличие iceberg.

        1. Достаточно ли тиков в кэше
        2. Проверить spoofer/iceberg на топ-уровнях
        3. Проверить объём на стороне
        4. Подтверждение тренда: цена идёт в сторону iceberg
        5. Подтверждение: N тиков подряд есть признаки iceberg
        """
        window = cache.window(self.lookback_ticks + 1)
        if len(window) < self.lookback_ticks + 1:
            self._reject("window")
            return None

        # 1. Проверяем аномалию объёма на топ-уровнях (iceberg ratio)
        bid_anomaly = self._check_level_anomaly(snap.bids)
        ask_anomaly = self._check_level_anomaly(snap.asks)

        if not bid_anomaly and not ask_anomaly:
            self._reject("no_anomaly")
            return None

        # 2. Минимальный объём
        if bid_anomaly and snap.total_bid_volume < self.min_volume_btc:
            self._reject("low_bid_volume")
            return None
        if ask_anomaly and snap.total_ask_volume < self.min_volume_btc:
            self._reject("low_ask_volume")
            return None

        # 3. Движение цены — подтверждение
        price_trend = self._price_trend(window)

        # 4. Iceberg на bid (накопление → BUY)
        if bid_anomaly and price_trend > 0:
            if self._confirm_iceberg(window, "bid"):
                confidence = min(
                    0.5 + abs(price_trend) * 5 + self._anomaly_strength(snap.bids),
                    0.95,
                )
                return OrderBookSignal(
                    pair=snap.pair,
                    side="BUY",
                    price=snap.ask_price,
                    strategy_name=self.name,
                    confidence=confidence,
                    reason=(
                        f"iceberg_bid "
                        f"ratio={self._max_level_ratio(snap.bids):.1f}x "
                        f"trend={price_trend:+.3f}%"
                    ),
                    exit_after_seconds=self.exit_after_seconds,
                    entry_tag="iceberg_buy",
                )

        # 5. Iceberg на ask (распределение → SELL)
        if ask_anomaly and price_trend < 0:
            if self._confirm_iceberg(window, "ask"):
                confidence = min(
                    0.5 + abs(price_trend) * 5 + self._anomaly_strength(snap.asks),
                    0.95,
                )
                return OrderBookSignal(
                    pair=snap.pair,
                    side="SELL",
                    price=snap.bid_price,
                    strategy_name=self.name,
                    confidence=confidence,
                    reason=(
                        f"iceberg_ask "
                        f"ratio={self._max_level_ratio(snap.asks):.1f}x "
                        f"trend={price_trend:+.3f}%"
                    ),
                    exit_after_seconds=self.exit_after_seconds,
                    entry_tag="iceberg_sell",
                )

        self._reject("no_confirmation")
        return None

    def custom_exit(self, trade: Trade, snap: OrderBookSnapshot,
                    cache: OrderBookCache) -> Optional[str]:
        """Выход: iceberg исчез или цена развернулась."""
        window = cache.window(3)
        if len(window) < 3:
            return None

        # Если iceberg пропал — выходим
        if trade.side == "BUY":
            if not self._check_level_anomaly(snap.bids):
                return "iceberg_gone_bid"
            # Или цена развернулась
            trend = self._price_trend(window)
            if trend < -0.02:  # -0.02% — разворот
                return "price_reversal"
        else:
            if not self._check_level_anomaly(snap.asks):
                return "iceberg_gone_ask"
            trend = self._price_trend(window)
            if trend > 0.02:
                return "price_reversal"

        return None

    # ── Приватные методы ─────────────────────────────────────────

    def _check_level_anomaly(self, levels: list[tuple[float, float]]) -> bool:
        """Аномалия объёма: уровень 1 в 3x+ больше уровня 2.

        Классический iceberg: большой ордер на одном уровне,
        а на следующем — нормальный объём.
        """
        if len(levels) < 3:
            return False
        vol_0 = levels[0][1]
        vol_1 = levels[1][1]
        vol_2 = levels[2][1]

        # Уровень 0 >> уровень 1 (iceberg на 0)
        if vol_1 > 0 and vol_0 / vol_1 >= self.iceberg_ratio:
            return True

        # Уровень 1 >> уровень 2 (iceberg на 1, 0 уже съели?)
        if vol_2 > 0 and vol_1 / vol_2 >= self.iceberg_ratio * 0.7:
            return True

        # Последовательный iceberg: vol_0 ~= vol_1 ~= vol_2 (одинаковый объём
        # на 3 уровнях — типичный iceberg, восстанавливает объём)
        if vol_0 > 0 and vol_1 > 0 and vol_2 > 0:
            pair_ratios = []
            for a, b in [(vol_0, vol_1), (vol_1, vol_2)]:
                if a > 0 and b > 0:
                    pair_ratios.append(max(a, b) / min(a, b))
            if pair_ratios and all(r < 1.5 for r in pair_ratios):
                avg_vol = (vol_0 + vol_1 + vol_2) / 3
                if avg_vol >= self.min_volume_btc:
                    return True

        return False

    def _max_level_ratio(self, levels: list[tuple[float, float]]) -> float:
        """Максимальное соотношение объёмов между соседними уровнями."""
        if len(levels) < 2:
            return 1.0
        max_r = 1.0
        for i in range(min(len(levels) - 1, 5)):
            v0 = levels[i][1]
            v1 = levels[i + 1][1]
            if v1 > 0:
                max_r = max(max_r, v0 / v1)
        return max_r

    def _anomaly_strength(self, levels: list[tuple[float, float]]) -> float:
        """Сила аномалии 0.0..0.3 для расчёта confidence."""
        if len(levels) < 2:
            return 0.0
        ratio = self._max_level_ratio(levels)
        return min((ratio - 1) / 10, 0.3)

    def _price_trend(self, window: list) -> float:
        """% изменение mid-цены за окно."""
        first = window[0].mid_price
        last = window[-1].mid_price
        if first <= 0:
            return 0.0
        return (last - first) / first * 100

    def _confirm_iceberg(self, window: list, side: str) -> bool:
        """Проверить что iceberg подтверждён N тиков подряд.

        Для confirmation_ticks проверяем — был ли iceberg
        хотя бы в половине тиков окна (чуток мягче для iceberg,
        т.к. он может появляться/исчезать между тиками).
        """
        recent = window[-self.confirmation_ticks:]
        anomalies = 0
        for snap in recent:
            if side == "bid":
                if self._check_level_anomaly(snap.bids):
                    anomalies += 1
            else:
                if self._check_level_anomaly(snap.asks):
                    anomalies += 1

        # Iceberg реже — достаточно 2 из 3 или 2 из 5
        threshold = max(2, self.confirmation_ticks // 2)
        return anomalies >= threshold
