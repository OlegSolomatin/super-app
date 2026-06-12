"""Trading signal model for Telegram-sourced signals.

Stores parsed signals from @brushscreener and @stairscreener channels.
Signals are classified by SignalMapper and stored for frontend display
and one-click strategy launching.
"""

from __future__ import annotations

from datetime import datetime
from typing import Any, Optional

from sqlalchemy import Boolean, Column, DateTime, Float, ForeignKey, Integer, String, Text, func
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import relationship

from app.core.database import Base


class TradingSignal(Base):
    """A trading signal parsed from Telegram screener channels."""

    __tablename__ = "trading_signals"

    id = Column(Integer, primary_key=True, autoincrement=True)
    user_id = Column(
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=True,
        index=True,
    )
    channel = Column(String(50), nullable=False, index=True)  # brushscreener / stairscreener
    exchange = Column(String(50), nullable=False)  # Mexc, Gate, Mexc Futures
    pair = Column(String(30), nullable=False, index=True)  # WOJAKUSDT
    price_range = Column(Float, nullable=True)
    vol_60m = Column(Float, nullable=True)
    vol_10m = Column(Float, nullable=True)

    # Stairs-specific
    slope = Column(Float, nullable=True)

    # Brush-specific
    top_ratio = Column(Float, nullable=True)
    bot_ratio = Column(Float, nullable=True)

    # Mapped strategy (filled by SignalMapper)
    mapped_strategy = Column(String(50), nullable=True)  # ers_scalping, stair_climber, etc.
    mapped_engine = Column(String(20), nullable=True)  # ob / trading
    mapped_params = Column(JSONB, nullable=True)  # Recommended params JSON
    mapped_exchange_fallback = Column(String(50), nullable=True)  # Alternative exchange
    mapped_available_exchanges = Column(JSONB, nullable=True)  # Dict of {exchange: bool}

    is_processed = Column(Boolean, default=False, server_default="false")
    created_at = Column(
        DateTime(timezone=True), server_default=func.now(), nullable=False, index=True
    )
    updated_at = Column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )

    # Relationship
    user = relationship("User", backref="trading_signals")

    def __repr__(self) -> str:
        return f"<TradingSignal #{self.id} {self.pair} on {self.exchange} ({self.channel})>"
