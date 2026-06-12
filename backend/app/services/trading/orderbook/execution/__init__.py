"""Execution module — связывает источник данных и биржу исполнения для OB-движка.

DataExchangeRouter: DataProvider → OrderBookEngine → ExchangeExecutor
"""
from app.services.trading.orderbook.execution.router import (
    DataExchangeRouter,
    ExchangeExecutor,
)

__all__ = [
    "DataExchangeRouter",
    "ExchangeExecutor",
]
