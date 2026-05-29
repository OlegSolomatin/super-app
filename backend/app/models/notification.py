"""
Notification model for super-app.

Tracks user notifications: likes, comments, follows, system alerts.
"""

from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import Boolean, Column, DateTime, ForeignKey, Index, String, Text, func
from sqlalchemy.dialects.postgresql import UUID

from app.core.database import Base


class Notification(Base):
    """User notification model."""

    __tablename__ = "notifications"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    type = Column(String(20), nullable=False)  # like, comment, system, follow
    title = Column(String(255), nullable=False)
    body = Column(Text, nullable=True)
    is_read = Column(Boolean, default=False, nullable=False)
    related_id = Column(UUID(as_uuid=True), nullable=True)
    created_at = Column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )

    # Relationships
    user = None  # Will be wired when needed

    __table_args__ = (
        Index("ix_notifications_user_read", "user_id", "is_read"),
        Index("ix_notifications_created_at", "created_at"),
    )

    def __repr__(self) -> str:
        return (
            f"<Notification id={self.id} user_id={self.user_id} "
            f"type={self.type} is_read={self.is_read}>"
        )
