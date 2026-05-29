"""Trading API endpoints.

GET    /trading/pairs               — Available trading pairs (hardcoded)
GET    /trading/strategies          — Available strategies (hardcoded)
GET    /trading/exchanges           — Available exchanges (hardcoded)
POST   /trading/runs                — Start a new trading run
GET    /trading/runs                — List all runs (filter by status)
GET    /trading/runs/{run_id}       — Run details
GET    /trading/runs/{run_id}/trades— Trades for a run
GET    /trading/runs/{run_id}/code  — Strategy code/logic
DELETE /trading/runs/{run_id}       — Stop/delete a run
"""

from __future__ import annotations

from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_session
from app.core.dependencies import get_current_user
from app.models.trading import TradingRun
from app.models.user import User
from app.schemas.trading import (
    ExchangeInfo,
    ExchangesListResponse,
    PairInfo,
    PairsListResponse,
    StrategiesListResponse,
    StrategyInfo,
    TradeListResponse,
    TradeResponse,
    TradingConfig,
    TradingResultResponse,
    TradingRunListResponse,
    TradingRunResponse,
    TradingRunStatus,
)

router = APIRouter(prefix="/trading", tags=["trading"])

# ---------------------------------------------------------------------------
# Hardcoded pair list
# ---------------------------------------------------------------------------
HARDCODED_PAIRS = [
    PairInfo(symbol="BTCUSDT", base="BTC", quote="USDT", min_qty=0.001, tick_size=0.01),
    PairInfo(symbol="ETHUSDT", base="ETH", quote="USDT", min_qty=0.01, tick_size=0.01),
    PairInfo(symbol="BNBUSDT", base="BNB", quote="USDT", min_qty=0.01, tick_size=0.01),
    PairInfo(symbol="SOLUSDT", base="SOL", quote="USDT", min_qty=0.1, tick_size=0.01),
    PairInfo(symbol="XRPUSDT", base="XRP", quote="USDT", min_qty=1.0, tick_size=0.0001),
    PairInfo(symbol="ADAUSDT", base="ADA", quote="USDT", min_qty=1.0, tick_size=0.0001),
    PairInfo(symbol="DOGEUSDT", base="DOGE", quote="USDT", min_qty=1.0, tick_size=0.00001),
    PairInfo(symbol="AVAXUSDT", base="AVAX", quote="USDT", min_qty=0.01, tick_size=0.01),
    PairInfo(symbol="DOTUSDT", base="DOT", quote="USDT", min_qty=0.1, tick_size=0.001),
    PairInfo(symbol="MATICUSDT", base="MATIC", quote="USDT", min_qty=1.0, tick_size=0.0001),
]

# ---------------------------------------------------------------------------
# Hardcoded strategy list
# ---------------------------------------------------------------------------
HARDCODED_STRATEGIES = [
    StrategyInfo(
        name="hammer",
        description="Hammer candlestick pattern — bullish reversal. Small body, long lower wick.",
        type="candle_pattern",
    ),
    StrategyInfo(
        name="inverse_hammer",
        description="Inverse Hammer candlestick pattern — bearish reversal. Small body, long upper wick.",
        type="candle_pattern",
    ),
]

# ---------------------------------------------------------------------------
# Hardcoded exchange list
# ---------------------------------------------------------------------------
HARDCODED_EXCHANGES = [
    ExchangeInfo(name="binance", display_name="Binance", supports_history=True, supports_websocket=True),
    ExchangeInfo(name="bybit", display_name="Bybit", supports_history=True, supports_websocket=True),
    ExchangeInfo(name="mock", display_name="Mock (test)", supports_history=True, supports_websocket=False),
]

# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------


@router.get("/pairs", response_model=PairsListResponse)
async def list_pairs(
    search: Optional[str] = Query(None, description="Filter by symbol substring"),
    page: int = Query(1, ge=1, description="Page number"),
    page_size: int = Query(20, ge=1, le=100, description="Items per page"),
) -> PairsListResponse:
    """Return available trading pairs with optional search and pagination."""
    items = HARDCODED_PAIRS
    if search:
        search_upper = search.upper()
        items = [p for p in items if search_upper in p.symbol.upper()]
    total = len(items)
    offset = (page - 1) * page_size
    page_items = items[offset : offset + page_size]
    return PairsListResponse(items=page_items, total=total)


@router.get("/strategies", response_model=StrategiesListResponse)
async def list_strategies() -> StrategiesListResponse:
    """Return available trading strategies."""
    return StrategiesListResponse(
        items=HARDCODED_STRATEGIES, total=len(HARDCODED_STRATEGIES)
    )


@router.get("/exchanges", response_model=ExchangesListResponse)
async def list_exchanges() -> ExchangesListResponse:
    """Return available exchange connectors."""
    return ExchangesListResponse(
        items=HARDCODED_EXCHANGES, total=len(HARDCODED_EXCHANGES)
    )


@router.post(
    "/runs",
    response_model=TradingRunResponse,
    status_code=status.HTTP_201_CREATED,
)
async def start_run(
    config: TradingConfig,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> TradingRunResponse:
    """Start a new trading run with the given configuration.

    Creates a database record and schedules the run via the trading engine.
    """
    # TODO: implement actual strategy execution
    raise HTTPException(
        status_code=status.HTTP_501_NOT_IMPLEMENTED,
        detail="Trading run execution is not yet implemented.",
    )


@router.get("/runs", response_model=TradingRunListResponse)
async def list_runs(
    status_filter: Optional[TradingRunStatus] = Query(
        None, alias="status", description="Filter by run status"
    ),
    page: int = Query(1, ge=1, description="Page number"),
    page_size: int = Query(20, ge=1, le=100, description="Items per page"),
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> TradingRunListResponse:
    """List all trading runs for the current user, with optional status filter."""
    stmt = select(TradingRun).where(TradingRun.user_id == current_user.id)
    if status_filter:
        stmt = stmt.where(TradingRun.status == status_filter.value)
    stmt = stmt.order_by(TradingRun.started_at.desc())
    result = await session.execute(stmt)
    runs = result.scalars().all()
    total = len(runs)
    items = [TradingRunResponse.model_validate(r) for r in runs]
    total_pages = max(1, (total + page_size - 1) // page_size)
    return TradingRunListResponse(
        items=items,
        total=total,
        page=page,
        page_size=page_size,
        total_pages=total_pages,
    )


@router.get("/runs/{run_id}", response_model=TradingRunResponse)
async def get_run(
    run_id: int,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> TradingRunResponse:
    """Return details of a specific trading run."""
    stmt = select(TradingRun).where(
        TradingRun.id == run_id,
        TradingRun.user_id == current_user.id,
    )
    result = await session.execute(stmt)
    run = result.scalar_one_or_none()
    if run is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Trading run not found.",
        )
    return TradingRunResponse.model_validate(run)


@router.get("/runs/{run_id}/trades", response_model=TradeListResponse)
async def get_run_trades(
    run_id: int,
    page: int = Query(1, ge=1, description="Page number"),
    page_size: int = Query(20, ge=1, le=100, description="Items per page"),
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> TradeListResponse:
    """Return trades associated with a specific trading run."""
    # Verify the run exists and belongs to the user
    stmt = select(TradingRun).where(
        TradingRun.id == run_id,
        TradingRun.user_id == current_user.id,
    )
    result = await session.execute(stmt)
    run = result.scalar_one_or_none()
    if run is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Trading run not found.",
        )
    # TODO: fetch trades from DB or trading engine
    return TradeListResponse(
        items=[],
        total=0,
        page=page,
        page_size=page_size,
        total_pages=1,
    )


@router.get("/runs/{run_id}/code")
async def get_run_strategy_code(
    run_id: int,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> dict:
    """Return the strategy code/logic used by a trading run."""
    stmt = select(TradingRun).where(
        TradingRun.id == run_id,
        TradingRun.user_id == current_user.id,
    )
    result = await session.execute(stmt)
    run = result.scalar_one_or_none()
    if run is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Trading run not found.",
        )
    # TODO: fetch strategy source code from a registry
    return {
        "run_id": run_id,
        "strategy": run.mode,
        "code": "# Strategy source code will be returned here",
    }


@router.delete("/runs/{run_id}", status_code=status.HTTP_204_NO_CONTENT)
async def stop_run(
    run_id: int,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> None:
    """Stop and delete a trading run."""
    stmt = select(TradingRun).where(
        TradingRun.id == run_id,
        TradingRun.user_id == current_user.id,
    )
    result = await session.execute(stmt)
    run = result.scalar_one_or_none()
    if run is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Trading run not found.",
        )
    # TODO: stop the strategy engine and delete the run
    await session.delete(run)
    return None
