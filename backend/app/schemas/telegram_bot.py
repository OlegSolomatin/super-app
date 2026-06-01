"""Pydantic schemas for Telegram bot notification settings."""

from __future__ import annotations

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field


class TelegramBotCreate(BaseModel):
    """Schema for creating a new Telegram bot notification configuration."""

    name: str = Field(..., min_length=1, max_length=100)
    bot_token: str = Field(..., min_length=1)
    chat_id: str = Field(..., min_length=1)


class TelegramBotResponse(BaseModel):
    """Schema for returning a Telegram bot configuration."""

    model_config = ConfigDict(from_attributes=True)

    id: UUID
    name: str
    bot_token: str  # Store securely in production
    chat_id: str
    created_at: datetime
