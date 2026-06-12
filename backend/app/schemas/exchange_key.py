"""Pydantic schemas for exchange API keys."""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field, field_validator


class ExchangeKeyCreate(BaseModel):
    """Payload for creating a new exchange API key."""

    exchange: str = Field(..., description="Exchange name (binance, mexc, bybit)")
    label: str = Field("", description="User-friendly label")
    api_key: str = Field(..., description="API key (plain text, encrypted at rest)")
    api_secret: str = Field(..., description="API secret (plain text, encrypted at rest)")
    passphrase: Optional[str] = Field(None, description="Passphrase for OKX etc.")


class ExchangeKeyUpdate(BaseModel):
    """Payload for updating an existing exchange API key."""

    label: Optional[str] = None
    api_key: Optional[str] = None
    api_secret: Optional[str] = None
    passphrase: Optional[str] = None
    is_active: Optional[bool] = None


class ExchangeKeyResponse(BaseModel):
    """Response model for exchange key (no secrets exposed)."""

    id: str
    exchange: str
    label: str
    is_active: bool
    status: str
    error_message: Optional[str] = None
    balance: Optional[float] = None
    balance_updated_at: Optional[datetime] = None
    last_checked_at: Optional[datetime] = None
    created_at: datetime
    updated_at: datetime

    model_config = {"from_attributes": True}

    @field_validator("id", mode="before")
    @classmethod
    def coerce_id(cls, v: object) -> str:
        if isinstance(v, uuid.UUID):
            return str(v)
        if isinstance(v, str):
            return v
        raise ValueError(f"Cannot coerce {type(v).__name__} to str")


class ExchangeKeyListResponse(BaseModel):
    """Response model for listing exchange keys."""

    items: list[ExchangeKeyResponse]
    total: int
