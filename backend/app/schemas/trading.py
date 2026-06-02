"""Pydantic schemas for the Trading module.

Defines API request/response models for trading runs, results, and trades.
"""

from __future__ import annotations

from datetime import datetime
from enum import Enum
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
        default=200, ge=10, le=500, description="SMA period for trend filter"
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
    type: str  # candle_pattern, indicator_based, ml
    nuances: Optional[str] = None  # Detailed info: SL, entry/exit, risk, etc.


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
