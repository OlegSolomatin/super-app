"""API endpoints for Order Book strategy runs.

Provides:
  - POST /api/v1/orderbook/start — start a new OB run
  - POST /api/v1/orderbook/stop — stop an active OB run
  - GET /api/v1/orderbook/runs — list user's OB runs
  - GET /api/v1/orderbook/runs/{run_id} — get OB run details
"""

from __future__ import annotations

from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import UUID4
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.database import get_session
from app.core.dependencies import get_current_user
from app.models.trading import OrderBookRun as DBOrderBookRun
from app.models.user import User
from app.schemas.trading import (
    OrderBookRunListResponse,
    OrderBookRunResponse,
    OrderBookStartRequest,
    OrderBookStatusResponse,
)
from app.services.trading.scheduler import scheduler

router = APIRouter(prefix="/orderbook", tags=["orderbook"])


@router.post("/start", response_model=OrderBookRunResponse, status_code=status.HTTP_201_CREATED)
async def start_orderbook_run(
    config: OrderBookStartRequest,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> OrderBookRunResponse:
    """Start a new Order Book strategy run."""
    # Check scheduler capacity
    if not scheduler.can_start():
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Достигнут лимит одновременных запусков (15). Остановите активный запуск.",
        )

    # Create DB record
    db_run = DBOrderBookRun(
        user_id=current_user.id,
        status="running",
        pair=config.pair,
        strategy=config.strategy,
        initial_balance=config.initial_balance,
        max_open_trades=config.max_open_trades,
        config_json=config.model_dump_json(),
    )
    session.add(db_run)
    await session.flush()

    await session.commit()

    # Reload
    stmt = select(DBOrderBookRun).where(DBOrderBookRun.id == db_run.id)
    result = await session.execute(stmt)
    db_run = result.scalar_one()

    # Schedule the run (fire-and-forget via asyncio task)
    await scheduler.start_orderbook_run(
        run_id=db_run.id,
        config=config.model_dump(),
    )

    return OrderBookRunResponse.model_validate(db_run)


@router.get("/runs", response_model=OrderBookRunListResponse)
async def list_orderbook_runs(
    status_filter: Optional[str] = Query(
        None, alias="status", description="Filter by run status"
    ),
    page: int = Query(1, ge=1, description="Page number"),
    page_size: int = Query(20, ge=1, le=100, description="Items per page"),
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> OrderBookRunListResponse:
    """List Order Book runs for the current user."""
    base_stmt = select(DBOrderBookRun).where(
        DBOrderBookRun.user_id == current_user.id
    )
    if status_filter:
        base_stmt = base_stmt.where(DBOrderBookRun.status == status_filter)

    # Count total
    count_stmt = select(func.count()).select_from(base_stmt.subquery())
    total = (await session.execute(count_stmt)).scalar() or 0

    # Paginate
    offset = (page - 1) * page_size
    stmt = (
        base_stmt
        .order_by(DBOrderBookRun.started_at.desc())
        .offset(offset)
        .limit(page_size)
    )
    result = await session.execute(stmt)
    runs = result.scalars().all()

    total_pages = max(1, (total + page_size - 1) // page_size)

    return OrderBookRunListResponse(
        items=[OrderBookRunResponse.model_validate(r) for r in runs],
        total=total,
        page=page,
        page_size=page_size,
        total_pages=total_pages,
    )


@router.get("/runs/{run_id}", response_model=OrderBookRunResponse)
async def get_orderbook_run(
    run_id: int,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> OrderBookRunResponse:
    """Get a single Order Book run by ID."""
    stmt = select(DBOrderBookRun).where(
        DBOrderBookRun.id == run_id,
        DBOrderBookRun.user_id == current_user.id,
    )
    result = await session.execute(stmt)
    db_run = result.scalar_one_or_none()
    if not db_run:
        raise HTTPException(status_code=404, detail="Run not found")
    return OrderBookRunResponse.model_validate(db_run)


@router.get("/runs/{run_id}/status", response_model=OrderBookStatusResponse)
async def get_orderbook_run_status(
    run_id: int,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> OrderBookStatusResponse:
    """Get live status for an active Order Book run (engine metrics, signals)."""
    # Verify the run belongs to this user
    stmt = select(DBOrderBookRun).where(
        DBOrderBookRun.id == run_id,
        DBOrderBookRun.user_id == current_user.id,
    )
    result = await session.execute(stmt)
    db_run = result.scalar_one_or_none()
    if not db_run:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="OrderBook run not found",
        )

    status_data = scheduler.get_engine_status(run_id)
    if status_data is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Engine is not running (run may be finished or cancelled)",
        )

    return OrderBookStatusResponse(**status_data)


@router.post("/stop")
async def stop_orderbook_run(
    run_id: int = Query(..., description="Run ID to stop"),
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> dict:
    """Stop an active Order Book run."""
    stmt = select(DBOrderBookRun).where(
        DBOrderBookRun.id == run_id,
        DBOrderBookRun.user_id == current_user.id,
    )
    result = await session.execute(stmt)
    db_run = result.scalar_one_or_none()

    if not db_run:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="OrderBook run not found",
        )

    if db_run.status != "running":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Run is not running (status: {db_run.status})",
        )

    await scheduler.stop_run(run_id=run_id)

    return {"detail": f"Run {run_id} stopping..."}
