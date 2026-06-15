"""Pydantic schemas for trading signals."""
from __future__ import annotations

from datetime import datetime
from typing import Any, Optional

from pydantic import BaseModel, ConfigDict


class TradingSignalResponse(BaseModel):
    """Response model for a trading signal."""

    model_config = ConfigDict(from_attributes=True)

    id: int
    channel: str
    exchange: str
    pair: str
    price_range: Optional[float] = None
    vol_60m: Optional[float] = None
    vol_10m: Optional[float] = None
    slope: Optional[float] = None
    top_ratio: Optional[float] = None
    bot_ratio: Optional[float] = None
    mapped_strategy: Optional[str] = None
    mapped_engine: Optional[str] = None
    mapped_params: Optional[dict[str, Any]] = None
    mapped_exchange_fallback: Optional[str] = None
    mapped_available_exchanges: Optional[dict[str, bool]] = None
    mapped_confidence: Optional[float] = None
    mapped_reasoning: Optional[str] = None
    is_processed: bool = False
    created_at: datetime


class TradingSignalListResponse(BaseModel):
    """Paginated list of trading signals."""

    items: list[TradingSignalResponse]
    total: int


class TradingSignalStartRequest(BaseModel):
    """Request to start a signal-based run."""

    mode: str = "virtual"  # "virtual" (реальные данные, виртуальный баланс) or "real"
    exchange: Optional[str] = None  # Биржа для запуска (например "bybit"). Если не указана — берётся из mapped_available_exchanges
    direction: Optional[str] = None  # "long" or "short" — из сигнала
    bot_id: Optional[str] = None  # Telegram bot ID for notifications
