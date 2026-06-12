"""ReplayDataProvider — воспроизведение записанных снапшотов.

DataProvider: реализует интерфейс DataProvider для backtesting.
Читает JSONL файл, записанный DataRecorder, и воспроизводит
снапшоты с заданной скоростью (или максимально быстро).

Использование:
    provider = ReplayDataProvider("snapshots_btc.jsonl", speed=10.0)
    await provider.start(callback)  # воспроизводит в 10x быстрее
"""
from __future__ import annotations

import asyncio
import json
import logging
import os
from datetime import datetime, timezone
from typing import Any, Callable, Coroutine, Optional

from app.services.trading.orderbook.data.base import DataProvider
from app.services.trading.orderbook.models import OrderBookSnapshot

logger = logging.getLogger(__name__)

# Минимальная задержка между снапшотами при максимальной скорости (сек)
MIN_DELAY = 0.001  # 1ms


class ReplayDataProvider(DataProvider):
    """DataProvider для backtesting OB-стратегий.

    Читает JSONL файл и передаёт снапшоты в callback
    с заданной скоростью воспроизведения.

    speed=1.0  — реальное время (как было записано)
    speed=10.0 — в 10x быстрее
    speed=0    — максимально быстро (без задержек)
    """

    def __init__(
        self,
        filepath: str,
        speed: float = 10.0,
        pairs: Optional[list[str]] = None,
    ):
        super().__init__(pairs or [])
        self._filepath = filepath
        self._speed = max(0.0, speed)
        self._callback: Optional[
            Callable[[OrderBookSnapshot], Coroutine[Any, Any, None]]
        ] = None
        self._running = False
        self._total = 0

    @property
    def name(self) -> str:
        return f"replay({os.path.basename(self._filepath)})"

    @property
    def total_snapshots(self) -> int:
        return self._total

    async def start(
        self,
        callback: Callable[[OrderBookSnapshot], Coroutine[Any, Any, None]],
    ) -> None:
        """Воспроизвести снапшоты из файла.

        DataProvider: реализация start().
        Читает JSONL, парсит, вызывает callback с задержками.

        Args:
            callback: Функция, вызываемая для каждого снапшота.
        """
        self._callback = callback
        self._running = True

        if not os.path.exists(self._filepath):
            logger.error(f"[ReplayDataProvider] File not found: {self._filepath}")
            return

        logger.info(
            f"[ReplayDataProvider] Replaying {self._filepath} "
            f"at {self._speed:.1f}x speed"
        )

        prev_timestamp: Optional[datetime] = None
        count = 0

        with open(self._filepath, "r", encoding="utf-8") as f:
            for line in f:
                if not self._running:
                    break

                line = line.strip()
                if not line:
                    continue

                try:
                    snap = self._parse_line(line)
                except (json.JSONDecodeError, KeyError, ValueError) as e:
                    logger.debug(f"[ReplayDataProvider] Skip line: {e}")
                    continue

                if snap is None:
                    continue

                # Задержка между снапшотами (симуляция реального времени)
                if prev_timestamp and self._speed > 0:
                    delta = (snap.timestamp - prev_timestamp).total_seconds()
                    if delta > 0:
                        delay = delta / self._speed
                        await asyncio.sleep(max(delay, MIN_DELAY))

                prev_timestamp = snap.timestamp
                count += 1

                if self._callback:
                    await self._callback(snap)

        self._total = count
        logger.info(
            f"[ReplayDataProvider] Done: {count} snapshots replayed from "
            f"{os.path.basename(self._filepath)}"
        )
        self._running = False

    def _parse_line(self, line: str) -> Optional[OrderBookSnapshot]:
        """Парсинг JSON строки -> OrderBookSnapshot."""
        data = json.loads(line)

        pair = data["pair"]
        timestamp = datetime.fromisoformat(data["timestamp"])
        bids = [(float(p), float(q)) for p, q in data["bids"]]
        asks = [(float(p), float(q)) for p, q in data["asks"]]

        return OrderBookSnapshot(
            pair=pair,
            timestamp=timestamp,
            bids=bids,
            asks=asks,
        )

    async def stop(self) -> None:
        """DataProvider: остановить воспроизведение."""
        self._running = False
        logger.info("[ReplayDataProvider] Stopped")
