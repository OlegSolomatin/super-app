"""API endpoints for trading signals.

GET  /trading/signals              — List recent signals
GET  /trading/signals/live         — List recent signals from Redis cache
GET  /trading/signals/live/stream  — SSE stream for real-time signals
GET  /trading/signals/{id}         — Signal details
POST /trading/signals/{id}/map     — Map/classify a signal
POST /trading/signals/{id}/start   — Start a run from a signal
"""

from __future__ import annotations

import asyncio
import json
from typing import AsyncIterator, Optional

from fastapi import APIRouter, Depends, HTTPException, Query, status
from fastapi.responses import StreamingResponse
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.cache import get_cache, publish, set_cache
from app.core.database import get_session
from app.core.dependencies import get_current_user
from app.models.trading import OrderBookRun as DBOrderBookRun
from app.models.trading import TradingConfig as DBTradingConfig
from app.models.trading import TradingRun as DBTradingRun
from app.models.trading_signal import TradingSignal
from app.models.user import User
from app.schemas.trading_signal import (
    TradingSignalListResponse,
    TradingSignalResponse,
    TradingSignalStartRequest,
)
from app.services.trading.scheduler import scheduler

router = APIRouter(prefix="/trading/signals", tags=["trading"])


# ── Live signals from Redis ───────────────────────────────────────────────


@router.get("/live")
async def list_live_signals(
    limit: int = Query(20, ge=1, le=50),
) -> list[dict]:
    """Return the latest signals from Redis cache (signals:latest list)."""
    from redis.asyncio import Redis

    from app.core.config import settings

    r = Redis.from_url(settings.REDIS_URL, encoding="utf-8", decode_responses=True)
    try:
        raw = await r.lrange("signals:latest", 0, limit - 1)
        return [json.loads(item) for item in raw]
    finally:
        await r.aclose()


@router.get("/live/stream")
async def stream_live_signals():
    """SSE endpoint: emits real-time signals as Server-Sent Events.

    Listens to Redis pub/sub channels:
      - channel:signal:new     — new raw signal
      - channel:signal:mapped  — signal classified by mapper
    """

    async def event_generator() -> AsyncIterator[str]:
        from redis.asyncio import Redis

        from app.core.config import settings

        r = Redis.from_url(
            settings.REDIS_URL, encoding="utf-8", decode_responses=True
        )
        pubsub = r.pubsub()
        try:
            await pubsub.subscribe("channel:signal:new", "channel:signal:mapped")

            # Send initial heartbeat
            yield "event: connected\ndata: {}\n\n"

            while True:
                try:
                    message = await pubsub.get_message(
                        timeout=20.0, ignore_subscribe_messages=True
                    )
                    if message is None:
                        # Keepalive ping every 20s
                        yield ": heartbeat\n\n"
                        continue

                    channel = message["channel"]
                    data = json.loads(message["data"])

                    if channel == "channel:signal:new":
                        yield f"event: signal:new\ndata: {json.dumps(data)}\n\n"
                    elif channel == "channel:signal:mapped":
                        yield f"event: signal:mapped\ndata: {json.dumps(data)}\n\n"
                except asyncio.TimeoutError:
                    yield ": heartbeat\n\n"
                except Exception:
                    await asyncio.sleep(1)
        finally:
            await pubsub.unsubscribe()
            await r.aclose()

    return StreamingResponse(
        event_generator(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",
        },
    )


# ── Signal list / detail ──────────────────────────────────────────────────


@router.get("", response_model=TradingSignalListResponse)
async def list_signals(
    limit: int = Query(20, ge=1, le=200, description="Number of signals to return"),
    channel: Optional[str] = Query(None, description="Filter by channel"),
    session: AsyncSession = Depends(get_session),
) -> TradingSignalListResponse:
    """Return the latest trading signals from Telegram screener channels."""
    stmt = select(TradingSignal).order_by(TradingSignal.created_at.desc())

    if channel:
        stmt = stmt.where(TradingSignal.channel == channel)

    stmt = stmt.limit(limit)
    result = await session.execute(stmt)
    signals = result.scalars().all()

    return TradingSignalListResponse(
        items=[TradingSignalResponse.model_validate(s) for s in signals],
        total=len(signals),
    )


@router.get("/{signal_id}", response_model=TradingSignalResponse)
async def get_signal(
    signal_id: int,
    session: AsyncSession = Depends(get_session),
) -> TradingSignalResponse:
    """Return details of a specific trading signal."""
    stmt = select(TradingSignal).where(TradingSignal.id == signal_id)
    result = await session.execute(stmt)
    signal = result.scalar_one_or_none()

    if signal is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Сигнал не найден.",
        )

    return TradingSignalResponse.model_validate(signal)


# ── Map signal ────────────────────────────────────────────────────────────


@router.post("/{signal_id}/map", response_model=TradingSignalResponse)
async def map_signal(
    signal_id: int,
    session: AsyncSession = Depends(get_session),
) -> TradingSignalResponse:
    """Classify a signal and update its mapped_* fields.

    Runs SignalMapper.classify() + cross-exchange lookup.
    """
    from app.services.signals.signal_mapper import map_and_save_signal

    stmt = select(TradingSignal).where(TradingSignal.id == signal_id)
    result = await session.execute(stmt)
    signal = result.scalar_one_or_none()

    if signal is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Сигнал не найден.",
        )

    classification = await map_and_save_signal(session, signal_id)

    if classification is None:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Ошибка классификации сигнала.",
        )

    # Re-fetch to get updated data
    stmt = select(TradingSignal).where(TradingSignal.id == signal_id)
    result = await session.execute(stmt)
    signal = result.scalar_one()

    return TradingSignalResponse.model_validate(signal)


# ── Start run from signal ─────────────────────────────────────────────────


@router.post("/{signal_id}/start", status_code=status.HTTP_201_CREATED)
async def start_signal_run(
    signal_id: int,
    body: TradingSignalStartRequest,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> dict:
    """Start a trading run from a signal.

    Uses the signal's mapped strategy and engine (OB or Trading).
    Creates DB record and delegates to scheduler.
    """
    stmt = select(TradingSignal).where(TradingSignal.id == signal_id)
    result = await session.execute(stmt)
    signal = result.scalar_one_or_none()

    if signal is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Сигнал не найден.",
        )

    if not signal.mapped_strategy or not signal.mapped_engine:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Сигнал ещё не классифицирован маппером. Попробуйте позже.",
        )

    if not scheduler.can_start():
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Достигнут лимит одновременных запусков (15). Остановите активный запуск.",
        )

    params = signal.mapped_params or {}

    if signal.mapped_engine == "ob":
        # ── OrderBook Engine ──
        from app.schemas.trading import OrderBookStartRequest

        ob_req = OrderBookStartRequest(
            pair=signal.pair,
            strategy=signal.mapped_strategy,
            initial_balance=params.get("balance", 10.0),
            max_open_trades=params.get("max_open", 1),
            stoploss=params.get("stoploss", -1.0),
            trailing_stop=params.get("trailing_stop", 0.3),
            max_hold_seconds=params.get("max_hold", 120),
            confirmation_ticks=params.get("conf_ticks", 2),
            max_spread=params.get("max_spread", 0.1),
            cooldown_seconds=params.get("cooldown", 120),
            auto_stop_hours=params.get("auto_stop", 1),
        )

        # Create DB record
        db_run = DBOrderBookRun(
            user_id=current_user.id,
            status="running",
            pair=signal.pair,
            strategy=signal.mapped_strategy,
            initial_balance=ob_req.initial_balance,
            max_open_trades=ob_req.max_open_trades,
            config_json=ob_req.model_dump_json(),
        )
        session.add(db_run)
        await session.flush()
        await session.commit()

        try:
            await scheduler.start_orderbook_run(
                run_id=db_run.id,
                config=ob_req.model_dump(),
            )
        except Exception as e:
            db_run.status = "error"
            db_run.error = str(e)
            await session.commit()
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=f"Ошибка запуска: {e}",
            )

        return {
            "engine": "ob",
            "run_id": db_run.id,
            "pair": signal.pair,
            "strategy": signal.mapped_strategy,
        }

    elif signal.mapped_engine == "trading":
        # ── Trading Engine ──
        from app.services.trading.models import TradingConfig as DomainTradingConfig
        from app.services.trading.models import TradingRunMode

        # Create DB run record
        db_run = DBTradingRun(
            user_id=current_user.id,
            status="running",
            mode="virtual",
        )
        session.add(db_run)
        await session.flush()

        db_config = DBTradingConfig(
            run_id=db_run.id,
            pair=signal.pair,
            strategy=signal.mapped_strategy,
            leverage=params.get("leverage", 3),
            virtual_balance=params.get("balance", 10.0),
            max_trade_amount=params.get("max_trade", 5.0),
            timeframe=params.get("timeframe", "3m"),
            duration_days=params.get("duration", 1),
            exchange="binance",
            stop_loss_percent=params.get("stoploss", 2.0),
            take_profit_percent=params.get("takeprofit", 5.0),
            trend_filter_enabled=False,
        )
        session.add(db_config)
        await session.commit()

        domain_config = DomainTradingConfig(
            mode=TradingRunMode.virtual,
            pair=signal.pair,
            strategy=signal.mapped_strategy,
            leverage=params.get("leverage", 3),
            virtual_balance=params.get("balance", 10.0),
            max_trade_amount=params.get("max_trade", 5.0),
            timeframe=params.get("timeframe", "3m"),
            duration_days=params.get("duration", 1),
            exchange="binance",
            stop_loss_percent=params.get("stoploss", 2.0),
            take_profit_percent=params.get("takeprofit", 5.0),
            trend_filter_enabled=False,
        )

        try:
            await scheduler.start_run(run_id=db_run.id, config=domain_config)
        except Exception as e:
            db_run.status = "error"
            db_run.error = str(e)
            await session.commit()
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=f"Ошибка запуска: {e}",
            )

        return {
            "engine": "trading",
            "run_id": db_run.id,
            "pair": signal.pair,
            "strategy": signal.mapped_strategy,
        }

    else:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Неизвестный движок: {signal.mapped_engine}",
        )
