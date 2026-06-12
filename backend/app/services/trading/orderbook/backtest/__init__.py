"""Backtesting для OB-стратегий.

Компоненты:
  - recorder.py: DataRecorder (запись live-снапшотов в файл)
  - replay_provider.py: ReplayDataProvider (воспроизведение из файла)
  - cli.py: CLI для запуска backtest
"""
from app.services.trading.orderbook.backtest.recorder import DataRecorder
from app.services.trading.orderbook.backtest.replay_provider import (
    ReplayDataProvider,
)

__all__ = [
    "DataRecorder",
    "ReplayDataProvider",
]
