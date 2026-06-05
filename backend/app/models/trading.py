"""SQLAlchemy models for the Trading module.

Defines database tables:
  - trading_runs           — individual strategy execution sessions
  - trading_results        — aggregated metrics per completed run
  - trading_trades         — individual buy/sell trades within a run
  - trading_configs        — snapshot of configuration for a run
"""

from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import (
    Boolean,
    Column,
    DateTime,
    Float,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    func,
    text,
)
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import relationship

from app.core.database import Base


class TradingRun(Base):
    """Trading strategy execution session."""

    __tablename__ = "trading_runs"

    id = Column(Integer, primary_key=True, autoincrement=True)
    user_id = Column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    status = Column(
        String(20), nullable=False, default="running", index=True
    )  # running, done, stopped, error
    mode = Column(
        String(20), nullable=False, default="history"
    )  # history, virtual, real
    started_at = Column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    finished_at = Column(DateTime(timezone=True), nullable=True)
    error = Column(Text, nullable=True)

    # Relationships
    config = relationship(
        "TradingConfig", back_populates="run", uselist=False, cascade="all, delete-orphan"
    )
    result = relationship(
        "TradingResult", back_populates="run", uselist=False, cascade="all, delete-orphan"
    )
    trades = relationship(
        "TradingTrade", back_populates="run", cascade="all, delete-orphan"
    )

    __table_args__ = (
        Index("ix_trading_runs_user_status", "user_id", "status"),
        Index("ix_trading_runs_started_at", "started_at"),
    )

    def __repr__(self) -> str:
        return (
            f"<TradingRun id={self.id} user_id={self.user_id} "
            f"status={self.status} mode={self.mode}>"
        )


class TradingConfig(Base):
    """Snapshot of the configuration used to start a trading run."""

    __tablename__ = "trading_configs"

    id = Column(Integer, primary_key=True, autoincrement=True)
    run_id = Column(
        Integer,
        ForeignKey("trading_runs.id", ondelete="CASCADE"),
        nullable=False,
        unique=True,
    )
    pair = Column(String(20), nullable=False, default="BTCUSDT")
    strategy = Column(String(50), nullable=False, default="hammer")
    leverage = Column(Integer, nullable=False, default=1)
    virtual_balance = Column(Float, nullable=False, default=10000.0)
    max_trade_amount = Column(Float, nullable=False, default=1000.0)
    timeframe = Column(String(10), nullable=False, default="1h")
    period_start = Column(DateTime(timezone=True), nullable=True)
    period_end = Column(DateTime(timezone=True), nullable=True)
    duration_days = Column(Integer, nullable=True)
    exchange = Column(String(50), nullable=True)
    notification_bot_id = Column(
        UUID(as_uuid=True),
        ForeignKey("telegram_bots.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )
    stop_loss_percent = Column(Float, nullable=True, default=2.0)
    take_profit_percent = Column(Float, nullable=True, default=5.0)
    trend_filter_enabled = Column(Boolean, nullable=False, server_default=text('true'), default=True)
    trend_filter_period = Column(Integer, nullable=False, server_default=text('50'), default=50)
    created_at = Column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )

    # Relationships
    run = relationship("TradingRun", back_populates="config")
    notification_bot = relationship(
        "TelegramBot", foreign_keys=[notification_bot_id]
    )

    def __repr__(self) -> str:
        return (
            f"<TradingConfig id={self.id} run_id={self.run_id} "
            f"pair={self.pair} strategy={self.strategy}>"
        )


class TradingResult(Base):
    """Aggregated performance metrics for a completed trading run."""

    __tablename__ = "trading_results"

    id = Column(Integer, primary_key=True, autoincrement=True)
    run_id = Column(
        Integer,
        ForeignKey("trading_runs.id", ondelete="CASCADE"),
        nullable=False,
        unique=True,
    )
    total_trades = Column(Integer, nullable=False, default=0)
    win_trades = Column(Integer, nullable=False, default=0)
    loss_trades = Column(Integer, nullable=False, default=0)
    win_rate = Column(Float, nullable=False, default=0.0)
    profit_loss = Column(Float, nullable=False, default=0.0)
    final_balance = Column(Float, nullable=False, default=0.0)
    max_drawdown = Column(Float, nullable=False, default=0.0)
    metrics = Column(JSONB, nullable=True, default=dict)
    created_at = Column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )

    # Relationships
    run = relationship("TradingRun", back_populates="result")

    def __repr__(self) -> str:
        return (
            f"<TradingResult id={self.id} run_id={self.run_id} "
            f"total_trades={self.total_trades} pnl={self.profit_loss}>"
        )


class TradingTrade(Base):
    """Individual buy/sell trade executed during a trading run."""

    __tablename__ = "trading_trades"

    id = Column(Integer, primary_key=True, autoincrement=True)
    run_id = Column(
        Integer,
        ForeignKey("trading_runs.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    side = Column(String(10), nullable=False)  # BUY / SELL
    pair = Column(String(20), nullable=True)  # Which pair (for pair-scanner runs)
    entry_price = Column(Float, nullable=False)
    exit_price = Column(Float, nullable=True)
    entry_time = Column(DateTime(timezone=True), nullable=False)
    exit_time = Column(DateTime(timezone=True), nullable=True)
    quantity = Column(Float, nullable=False)
    pnl = Column(Float, nullable=False, default=0.0)
    pnl_percent = Column(Float, nullable=False, default=0.0)
    status = Column(
        String(10), nullable=False, default="open", index=True
    )  # open / closed

    # Relationships
    run = relationship("TradingRun", back_populates="trades")

    __table_args__ = (
        Index("ix_trading_trades_run_status", "run_id", "status"),
        Index("ix_trading_trades_entry_time", "entry_time"),
    )

    def __repr__(self) -> str:
        return (
            f"<TradingTrade id={self.id} run_id={self.run_id} "
            f"side={self.side} status={self.status}>"
        )


class TradingPairLock(Base):
    """Temporary lock on a pair after a losing trade.
    
    Prevents re-entering the same pair until the lock expires.
    """

    __tablename__ = "trading_pairlocks"

    id = Column(Integer, primary_key=True, autoincrement=True)
    pair = Column(String(20), nullable=False, index=True)
    until = Column(DateTime(timezone=True), nullable=False)
    reason = Column(String(255), nullable=True)
    created_at = Column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )

    def __repr__(self) -> str:
        return (
            f"<TradingPairLock pair={self.pair} until={self.until}>"
        )


class OrderBookRun(Base):
    """Order Book strategy execution session (imbalance scalping etc.)."""

    __tablename__ = "orderbook_runs"

    id = Column(Integer, primary_key=True, autoincrement=True)
    user_id = Column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    status = Column(
        String(20), nullable=False, default="running", index=True
    )  # running, done, stopped, error
    pair = Column(String(20), nullable=False, default="BTCUSDT")
    strategy = Column(String(50), nullable=False, default="imbalance_scalping")
    initial_balance = Column(Float, nullable=False, default=1000.0)
    max_open_trades = Column(Integer, nullable=False, default=1)
    started_at = Column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    finished_at = Column(DateTime(timezone=True), nullable=True)
    error = Column(Text, nullable=True)

    # Результаты (заполняются после остановки engine)
    metrics_json = Column(Text, nullable=True)
    total_pnl = Column(Float, nullable=True, default=0.0)
    total_trades = Column(Integer, nullable=True, default=0)
    win_trades = Column(Integer, nullable=True, default=0)
    loss_trades = Column(Integer, nullable=True, default=0)
    final_balance = Column(Float, nullable=True)

    # Live-status (обновляются engine в реальном времени)
    current_balance = Column(Float, nullable=True)
    open_trade_json = Column(Text, nullable=True)

    __table_args__ = (
        Index("ix_ob_runs_user_status", "user_id", "status"),
        Index("ix_ob_runs_started_at", "started_at"),
    )

    def __repr__(self) -> str:
        return (
            f"<OrderBookRun id={self.id} user_id={self.user_id} "
            f"status={self.status} pair={self.pair} strategy={self.strategy}>"
        )
