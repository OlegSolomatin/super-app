"""SQLAlchemy model for exchange API keys (encrypted at rest)."""

from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import Boolean, Column, DateTime, Float, ForeignKey, String, Text, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship

from app.core.database import Base


class ExchangeKey(Base):
    """Encrypted API key for a cryptocurrency exchange.

    Keys are encrypted at rest using Fernet symmetric encryption.
    """

    __tablename__ = "exchange_keys"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    exchange = Column(String(20), nullable=False)  # binance, mexc, bybit
    label = Column(String(100), default="")  # user-friendly name

    # Encrypted at rest
    api_key_encrypted = Column(Text, nullable=False)
    api_secret_encrypted = Column(Text, nullable=False)
    passphrase = Column(Text, nullable=True)  # For exchanges that need it (e.g. OKX)

    # Status
    is_active = Column(Boolean, default=True, nullable=False)
    status = Column(
        String(20), default="untested", nullable=False
    )  # untested, valid, invalid

    # Balance snapshot
    balance = Column(Float, nullable=True)
    balance_updated_at = Column(DateTime(timezone=True), nullable=True)

    # Metadata
    created_at = Column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at = Column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
        nullable=False,
    )
    last_checked_at = Column(DateTime(timezone=True), nullable=True)

    # Relationships
    user = relationship("User", backref="exchange_keys")

    def __repr__(self) -> str:
        return f"<ExchangeKey id={self.id} exchange={self.exchange} status={self.status}>"
