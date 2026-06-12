"""DataRecorder — запись снапшотов стакана в файл для последующего backtesting.

Использование:
    recorder = DataRecorder("snapshots_btc.jsonl")
    recorder.record(snap)  # вызывается из engine._on_snapshot
    recorder.close()

Формат: JSONL (одна строка = один OrderBookSnapshot в JSON)
"""
from __future__ import annotations

import json
import logging
import os
from datetime import datetime, timezone
from typing import Optional

from app.services.trading.orderbook.models import OrderBookSnapshot

logger = logging.getLogger(__name__)

SNAPSHOTS_DIR = os.path.join(
    os.path.dirname(__file__), "..", "..", "..", "..", "data", "ob_snapshots"
)


class DataRecorder:
    """Запись снапшотов в JSONL файл для backtesting.

    Создаёт файл с именем: {pair}_{strategy}_{timestamp}.jsonl
    Каждая строка — один снапшот в JSON.
    """

    def __init__(
        self,
        pair: str,
        strategy: str = "",
        output_dir: str = "",
    ):
        os.makedirs(output_dir or SNAPSHOTS_DIR, exist_ok=True)
        timestamp = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
        safe_pair = pair.replace("/", "_")
        filename = f"{safe_pair}_{strategy}_{timestamp}.jsonl"
        filepath = os.path.join(output_dir or SNAPSHOTS_DIR, filename)

        self._filepath = filepath
        self._file = open(filepath, "w", encoding="utf-8")
        self._count = 0
        logger.info(f"[DataRecorder] Recording to {filepath}")

    def record(self, snap: OrderBookSnapshot) -> None:
        """Записать один снапшот в файл."""
        if not self._file:
            return

        data = {
            "pair": snap.pair,
            "timestamp": snap.timestamp.isoformat(),
            "bids": [(round(p, 2), round(q, 6)) for p, q in snap.bids],
            "asks": [(round(p, 2), round(q, 6)) for p, q in snap.asks],
            "mid_price": snap.mid_price,
            "spread_pct": snap.spread_pct,
            "imbalance": snap.imbalance,
            "total_bid_volume": snap.total_bid_volume,
            "total_ask_volume": snap.total_ask_volume,
        }
        self._file.write(json.dumps(data, default=str) + "\n")
        self._count += 1

    @property
    def count(self) -> int:
        return self._count

    @property
    def filepath(self) -> str:
        return self._filepath

    def close(self) -> None:
        """Закрыть файл."""
        if self._file:
            self._file.close()
            logger.info(
                f"[DataRecorder] Closed {self._filepath} "
                f"({self._count} snapshots)"
            )
            self._file = None

    def __del__(self):
        self.close()
