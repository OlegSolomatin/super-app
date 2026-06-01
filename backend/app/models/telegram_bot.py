"""SQLAlchemy model for Telegram notification bots."""

from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import Column, DateTime, ForeignKey, String, Text, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship

from app.core.database import Base


class TelegramBot(Base):
    """Telegram bot config for notifications."""

    __tablename__ = "telegram_bots"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    name = Column(String(100), nullable=False)
    bot_token = Column(Text, nullable=False)
    chat_id = Column(String(50), nullable=False)
    created_at = Column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )

    # Relationship
    user = relationship("User", backref="telegram_bots")

    def __repr__(self) -> str:
        return f"<TelegramBot id={self.id} name={self.name}>"
