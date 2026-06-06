"""Pydantic schemas for the Trading module.

Defines API request/response models for trading runs, results, and trades.
"""

from __future__ import annotations

from datetime import datetime
from enum import Enum
import json
from typing import Any, List, Optional
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator


class TradingRunMode(str, Enum):
    """Run mode for a trading strategy execution."""

    history = "history"
    virtual = "virtual"
    real = "real"


class TradingRunStatus(str, Enum):
    """Status of a trading run."""

    running = "running"
    done = "done"
    stopped = "stopped"
    error = "error"


# ---------- request ----------


class TradingConfig(BaseModel):
    """Full configuration for starting a trading run."""

    mode: TradingRunMode = TradingRunMode.history
    pair: str = Field(default="BTCUSDT", description="Trading pair symbol")
    strategy: str = Field(default="hammer", description="Strategy name")
    leverage: int = Field(default=1, ge=1, le=100, description="Leverage 1-100x")
    virtual_balance: float = Field(
        default=10000.0, ge=0, description="Virtual balance for history/virtual mode"
    )
    max_trade_amount: float = Field(
        default=1000.0, ge=0, description="Maximum amount per trade"
    )
    timeframe: str = Field(
        default="1h",
        description="Candle timeframe: 1m, 5m, 15m, 30m, 1h, 4h, 1d, 1w, 30d",
    )
    period_start: Optional[datetime] = Field(
        default=None, description="Start of historical period"
    )
    period_end: Optional[datetime] = Field(
        default=None, description="End of historical period"
    )
    duration_days: Optional[int] = Field(
        default=None, ge=1, description="Duration in days for virtual/real mode"
    )
    exchange: Optional[str] = Field(
        default=None, description="Exchange name for real mode"
    )
    notification_bot_id: Optional[str] = Field(
        default=None, description="Telegram bot ID for notifications"
    )
    stop_loss_percent: Optional[float] = Field(
        default=None, ge=0, le=100, description="Stop loss percent"
    )
    take_profit_percent: Optional[float] = Field(
        default=None, ge=0, le=1000, description="Take profit percent"
    )
    trend_filter_enabled: bool = Field(
        default=True, description="Enable trend filter (price above SMA)"
    )
    trend_filter_period: int = Field(
        default=50, ge=10, le=500, description="SMA period for trend filter"
    )


# ---------- responses ----------


class TradingResultResponse(BaseModel):
    """Aggregated result of a completed trading run."""

    model_config = ConfigDict(from_attributes=True)

    run_id: int
    total_trades: int = 0
    win_trades: int = 0
    loss_trades: int = 0
    win_rate: float = 0.0
    profit_loss: float = 0.0
    final_balance: float = 0.0
    max_drawdown: float = 0.0
    metrics: dict[str, Any] = Field(default_factory=dict)


class TradingRunResponse(BaseModel):
    """Response model for a trading run."""

    model_config = ConfigDict(from_attributes=True)

    id: int
    user_id: UUID
    status: TradingRunStatus
    mode: TradingRunMode
    config: Optional[TradingConfig] = None
    result: Optional[TradingResultResponse] = None
    started_at: datetime
    finished_at: Optional[datetime] = None
    error: Optional[str] = None

    @field_validator("user_id", mode="before")
    @classmethod
    def coerce_user_id(cls, v: Any) -> UUID:
        if isinstance(v, UUID):
            return v
        if isinstance(v, str):
            return UUID(v)
        raise ValueError(f"Invalid user_id: {v}")

    @model_validator(mode="before")
    @classmethod
    def coerce_config(cls, data: Any) -> Any:
        if isinstance(data, dict):
            return data
        result = {
            "id": data.id,
            "user_id": data.user_id,
            "status": data.status,
            "mode": data.mode,
            "started_at": data.started_at,
            "finished_at": data.finished_at,
            "error": data.error,
        }
        cfg = getattr(data, "config", None)
        if cfg is not None and not isinstance(cfg, dict) and not isinstance(cfg, BaseModel):
            from app.models.trading import TradingConfig as DBTradingConfig
            if isinstance(cfg, DBTradingConfig):
                run_mode = data.mode if hasattr(data, "mode") else "history"
                result["config"] = {
                    "mode": run_mode if isinstance(run_mode, str) else run_mode.value,
                    "pair": cfg.pair or "",
                    "strategy": cfg.strategy or "",
                    "leverage": cfg.leverage or 1,
                    "virtual_balance": cfg.virtual_balance or 1000,
                    "max_trade_amount": cfg.max_trade_amount or 100,
                    "timeframe": cfg.timeframe or "1h",
                    "period_start": cfg.period_start,
                    "period_end": cfg.period_end,
                    "duration_days": cfg.duration_days,
                    'exchange': cfg.exchange,
                    'notification_bot_id': str(cfg.notification_bot_id) if cfg.notification_bot_id is not None else None,
                    'stop_loss_percent': cfg.stop_loss_percent if cfg.stop_loss_percent is not None else None,
                    'take_profit_percent': cfg.take_profit_percent if cfg.take_profit_percent is not None else None,
                    'trend_filter_enabled': cfg.trend_filter_enabled if cfg.trend_filter_enabled is not None else True,
                    'trend_filter_period': cfg.trend_filter_period if cfg.trend_filter_period is not None else 200,
                }
        # Include result data
        res = getattr(data, "result", None)
        if res is not None:
            result["result"] = {
                "run_id": res.run_id,
                "total_trades": res.total_trades or 0,
                "win_trades": res.win_trades or 0,
                "loss_trades": res.loss_trades or 0,
                "win_rate": res.win_rate or 0.0,
                "profit_loss": res.profit_loss or 0.0,
                "final_balance": res.final_balance or 0.0,
                "max_drawdown": res.max_drawdown or 0.0,
                "metrics": res.metrics or {},
            }
        return result


class TradeResponse(BaseModel):
    """Response model for a single trade within a run."""

    model_config = ConfigDict(from_attributes=True)

    id: int
    run_id: int
    side: str  # BUY / SELL
    pair: Optional[str] = None  # Which pair (for pair-scanner runs)
    entry_price: float
    exit_price: Optional[float] = None
    entry_time: datetime
    exit_time: Optional[datetime] = None
    quantity: float
    pnl: float = 0.0
    pnl_percent: float = 0.0
    status: str = "open"  # open / closed


# ---------- helper: pair / strategy / exchange listings ----------


class PairInfo(BaseModel):
    """Trading pair metadata."""

    symbol: str
    base: str
    quote: str
    min_qty: float
    tick_size: float
    icon_url: Optional[str] = None


class StrategyInfo(BaseModel):
    """Strategy metadata."""

    name: str
    description: str
    type: str  # candle_pattern, indicator_based, ml, pair_scanner
    nuances: Optional[str] = None  # Detailed info: SL, entry/exit, risk, etc.
    is_pair_scanner: bool = False  # If True, scans all pairs (pair selector hidden)


class ExchangeInfo(BaseModel):
    """Exchange metadata."""

    name: str
    display_name: str
    supports_history: bool = True
    supports_websocket: bool = False


class PairsListResponse(BaseModel):
    """Response with available trading pairs."""

    items: List[PairInfo]
    total: int


class StrategiesListResponse(BaseModel):
    """Response with available strategies."""

    items: List[StrategyInfo]
    total: int


class ExchangesListResponse(BaseModel):
    """Response with available exchanges."""

    items: List[ExchangeInfo]
    total: int


class TradingRunListResponse(BaseModel):
    """Paginated list of trading runs."""

    items: List[TradingRunResponse]
    total: int
    page: int
    page_size: int
    total_pages: int


class TradeListResponse(BaseModel):
    """Paginated list of trades for a run."""

    items: List[TradeResponse]
    total: int
    page: int
    page_size: int
    total_pages: int


# Rebuild models with forward references and __future__ annotations
TradingRunResponse.model_rebuild()


# ── Order Book schemas ───────────────────────────────────────────────


class OrderBookStartRequest(BaseModel):
    """Request body for starting an Order Book strategy run."""

    pair: str = Field(default="BTCUSDT", description="Trading pair")
    strategy: str = Field(
        default="imbalance_scalping", description="OB strategy name"
    )
    initial_balance: float = Field(
        default=1000.0, ge=100, le=1_000_000, description="Virtual balance"
    )
    max_open_trades: int = Field(
        default=1, ge=1, le=10, description="Max concurrent trades"
    )
    stoploss: float = Field(default=-1.0, ge=-5.0, le=0.0, description="Stop loss %")
    trailing_stop: float = Field(default=0.3, ge=0, le=2.0, description="Trailing stop %")
    trailing_offset: float = Field(default=0.5, ge=0, le=2.0, description="Trailing offset %")
    max_hold_seconds: int = Field(default=120, ge=10, le=600, description="Max hold time")
    confirmation_ticks: int = Field(default=3, ge=1, le=10)
    max_spread: float = Field(default=0.05, ge=0.01, le=0.5)
    cooldown_seconds: int = Field(default=120, ge=10, le=600)
    auto_stop_hours: int = Field(
        default=0, ge=0, le=72, description="Auto-stop after N hours (0 = unlimited)"
    )

    # Spread Capture params
    min_spread_pct: Optional[float] = Field(default=None, ge=0.01, le=1.0)
    spread_entry_threshold: Optional[float] = Field(default=None, ge=0.01, le=1.0)
    spread_exit_threshold: Optional[float] = Field(default=None, ge=0.001, le=1.0)

    # Order Flow Momentum params
    flow_threshold_volume: Optional[float] = Field(default=None, ge=100, le=1_000_000)
    min_flow_signals: Optional[int] = Field(default=None, ge=1, le=10)
    flow_exit_seconds: Optional[int] = Field(default=None, ge=5, le=300)


class OrderBookRunResponse(BaseModel):
    """Response model for an Order Book run."""

    model_config = ConfigDict(from_attributes=True)

    id: int
    user_id: UUID
    status: TradingRunStatus
    pair: str
    strategy: str
    initial_balance: float
    max_open_trades: int
    started_at: datetime
    finished_at: Optional[datetime] = None
    error: Optional[str] = None
    total_trades: Optional[int] = None
    total_pnl: Optional[float] = None
    final_balance: Optional[float] = None
    current_balance: Optional[float] = None
    open_trade_json: Optional[str] = None
    config: Optional[dict] = None

    @field_validator("user_id", mode="before")
    @classmethod
    def coerce_user_id(cls, v: Any) -> UUID:
        if isinstance(v, UUID):
            return v
        if isinstance(v, str):
            return UUID(v)
        return v

    @field_validator("status", mode="before")
    @classmethod
    def coerce_status(cls, v: Any) -> TradingRunStatus:
        if isinstance(v, TradingRunStatus):
            return v
        if isinstance(v, str):
            return TradingRunStatus(v)
        return v

    @model_validator(mode="before")
    @classmethod
    def parse_config_json(cls, data: Any) -> Any:
        # ORM-режим (from_attributes=True): конвертируем в dict с config
        if not isinstance(data, dict):
            config_json = getattr(data, "config_json", None)
            if isinstance(config_json, str):
                result = {}
                for col in data.__table__.columns:
                    result[col.name] = getattr(data, col.name)
                try:
                    result["config"] = json.loads(config_json)
                except (json.JSONDecodeError, TypeError):
                    result["config"] = None
                return result
            return data

        # Dict-режим
        config_json = data.get("config_json")
        if isinstance(config_json, str):
            try:
                data["config"] = json.loads(config_json)
            except (json.JSONDecodeError, TypeError):
                data["config"] = None
        data.pop("config_json", None)
        return data


class OrderBookRunListResponse(BaseModel):
    """Paginated list of order book runs."""

    items: List[OrderBookRunResponse]
    total: int
    page: int
    page_size: int
    total_pages: int


class OrderBookStatusResponse(BaseModel):
    """Live status of an OB engine run (from engine.status)."""

    running: bool
    pair: str
    strategy: str
    balance: float
    free_balance: float
    open_trades: dict
    metrics: dict
    active_locks: list
    recent_signals: list[dict]
