"""
Pydantic schemas for Notification entity.

Uses Pydantic v2 with from_attributes=True for ORM mode.
"""

from __future__ import annotations

from datetime import datetime
from typing import Optional

from pydantic import BaseModel, ConfigDict, Field


class NotificationRead(BaseModel):
    """Notification response model."""

    model_config = ConfigDict(from_attributes=True)

    id: str
    user_id: str
    type: str
    title: str
    body: Optional[str] = None
    is_read: bool = False
    related_id: Optional[str] = None
    created_at: datetime


class NotificationPaginated(BaseModel):
    """Paginated list of notifications."""

    items: list[NotificationRead]
    total: int
    page: int
    page_size: int
    total_pages: int


class UnreadCountResponse(BaseModel):
    """Response with unread notification count."""

    unread_count: int
