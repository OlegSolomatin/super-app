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
    logger = __import__("logging").getLogger(__name__)

    # ── Determine exchange for data/trading ───────────────────────────
    # Priority:
    #   1. Explicit body.exchange (from UI)
    #   2. Any exchange where user has API key AND pair exists
    #   3. Signal's original exchange (e.g., Gate, MEXC)
    #   4. Binance (default fallback)
    selected_exchange: str | None = None

    # 1. Из запроса (если передан)
    if body.exchange:
        selected_exchange = body.exchange.lower()
        logger.info("Signal #%d: exchange forced by request: %s", signal_id, selected_exchange)

    # 2. Smart routing: check user keys + pair availability
    else:
        from app.models.exchange_key import ExchangeKey
        from app.services.trading.exchange.ccxt_exchange import create_exchange
        from sqlalchemy import select as sa_select

        # Get all exchanges with valid keys
        key_stmt = sa_select(ExchangeKey.exchange).where(
            ExchangeKey.status == "valid",
        ).distinct()
        key_result = await session.execute(key_stmt)
        exchanges_with_keys = [row[0] for row in key_result]

        if exchanges_with_keys:
            logger.info(
                "Signal #%d: checking pair %s on %d exchange(s) with keys: %s",
                signal_id, signal.pair, len(exchanges_with_keys),
                exchanges_with_keys,
            )

            # Check pair availability on all exchanges with keys (in parallel)
            async def _check_pair(exch: str) -> tuple[str, bool]:
                try:
                    ex = create_exchange(exch)
                    ticker = await ex.get_ticker(signal.pair)
                    if ticker and ticker.get("volume", 0) > 0:
                        return exch, True
                except Exception:
                    pass
                return exch, False

            results = await asyncio.gather(
                *[_check_pair(exch) for exch in exchanges_with_keys],
                return_exceptions=True,
            )

            matched_exchanges = []
            for res in results:
                if not isinstance(res, Exception) and len(res) == 2 and res[1]:
                    matched_exchanges.append(res[0])

            if matched_exchanges:
                selected_exchange = matched_exchanges[0]
                logger.info(
                    "Signal #%d: using exchange with valid key '%s' (pair %s found)",
                    signal_id, selected_exchange, signal.pair,
                )

        # 3. Fall back to signal's exchange (from parser)
        if not selected_exchange:
            signal_exchange = (signal.exchange or "").split(" - ")[0].split(" ")[0].strip().lower()
            if signal_exchange and signal_exchange not in ("", "none", "unknown"):
                selected_exchange = signal_exchange
                logger.info(
                    "Signal #%d: no key match, using signal exchange: %s",
                    signal_id, selected_exchange,
                )

        # 4. Ultimate fallback
        if not selected_exchange:
            selected_exchange = "binance"
            logger.info("Signal #%d: no exchange found, defaulting to binance", signal_id)

    logger.info("Selected exchange for signal #%d: %s (mode=%s)", signal_id, selected_exchange, body.mode)

    # ── Real mode checks ──────────────────────────────────────────────
    if body.mode == "real":
        from sqlalchemy import select as sa_select

        active_real = await session.execute(
            sa_select(DBTradingRun).where(
                DBTradingRun.mode == "real",
                DBTradingRun.status == "running",
            ).limit(1)
        )
        if active_real.scalar_one_or_none() is not None:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Другой реальный запуск уже активен. Максимум 1 real-запуск единовременно. "
                       "Остановите активный перед запуском нового.",
            )

        # OB engine не поддерживает real — форсируем virtual
        if signal.mapped_engine == "ob":
            logger.info("OB engine does not support real mode — launching in virtual")
            body.mode = "virtual"

    # Force virtual mode for safety (real mode is opt-in via body.mode="real")
    is_virtual = body.mode != "real"

    # ── Direction ─────────────────────────────────────────────────────
    direction = body.direction or (signal.mapped_params or {}).get("direction", "long")

    # ═══════════════════════════════════════════════════════════════════
    # OrderBook Engine
    # ═══════════════════════════════════════════════════════════════════
    if signal.mapped_engine == "ob":
        # ── Validate pair exists on selected or signal exchange ──
        from app.schemas.trading import OrderBookStartRequest
        from app.services.trading.exchange.ccxt_exchange import create_exchange

        async def _check_ob_exchange(pair: str, preferred: str | None = None) -> str | None:
            """Check if pair exists on exchange, trying preferred first, then binance/bybit."""
            import httpx

            # 1. Проверяем предпочтительную биржу (selected_exchange или биржу из сигнала)
            if preferred and preferred not in ("binance", "bybit"):
                try:
                    ex = create_exchange(preferred)
                    ticker = await ex.get_ticker(pair)
                    if ticker and ticker.get("volume", 0) > 0:
                        logger.info("OB pair %s found on signal exchange: %s", pair, preferred)
                        return preferred
                except Exception:
                    pass

            # 2. Проверяем Binance и Bybit (WS-биржи)
            for exchange_name in ("binance", "bybit"):
                try:
                    if exchange_name == "binance":
                        async with httpx.AsyncClient(timeout=5) as client:
                            resp = await client.get(
                                f"https://api.binance.com/api/v3/ticker/price?symbol={pair}"
                            )
                            if resp.status_code == 200:
                                return "binance"
                    elif exchange_name == "bybit":
                        async with httpx.AsyncClient(timeout=5) as client:
                            resp = await client.get(
                                f"https://api.bybit.com/v5/market/tickers?category=spot&symbol={pair}"
                            )
                            if resp.status_code == 200:
                                data = resp.json()
                                if data.get("retCode") == 0:
                                    return "bybit"
                except Exception:
                    continue

            # 3. Если preferred не Binance/Bybit и не прошёл проверку выше — пробуем всё равно
            # (могла быть ошибка тикера, но пара реально существует)
            if preferred:
                logger.warning("OB pair %s check on %s failed with ticker, but using it anyway", pair, preferred)
                return preferred

            return None

        # Определяем предпочтительную биржу для OB: selected_exchange (если определён) или биржа из сигнала
        ob_preferred = selected_exchange
        if not ob_preferred:
            ob_exchange_raw = (signal.exchange or "").strip()
            if ob_exchange_raw and ob_exchange_raw.lower() not in ("", "none", "unknown"):
                ob_preferred = ob_exchange_raw  # полное имя "Mexc - Futures"
        if ob_preferred and ob_preferred.lower() in ("", "none", "unknown"):
            ob_preferred = None

        ob_source_exchange = await _check_ob_exchange(signal.pair, preferred=ob_preferred)
        if not ob_source_exchange:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Пара {signal.pair} не найдена. "
                       f"OB стратегии ({signal.mapped_strategy}) требуют стакан. "
                       f"Проверьте что пара существует на выбранной бирже.",
            )

        # Build OrderBookStartRequest with common params + strategy-specific
        ob_kwargs = dict(
            pair=signal.pair,
            strategy=signal.mapped_strategy,
            initial_balance=params.get("balance", 10.0),
            max_open_trades=params.get("max_open", 1),
            stoploss=params.get("stoploss", -1.0),
            trailing_stop=params.get("trailing_stop", 0.3),
            max_hold_seconds=params.get("max_hold", 120),
            confirmation_ticks=params.get("conf_ticks", 1),
            max_spread=params.get("max_spread", 0.1),
            cooldown_seconds=params.get("cooldown", 120),
            auto_stop_hours=params.get("auto_stop", 1),
        )
        # Pass through strategy-specific params if present in mapped_params
        for ob_field in (
            "ers_min_imbalance", "ers_min_profit_pct", "ers_exit_on_reversion",
            "ers_max_hold_seconds", "ers_min_volume",
            "imbalance_threshold", "surge_pct",
            "min_spread_pct", "spread_entry_threshold", "spread_exit_threshold",
            "flow_threshold_volume", "min_flow_signals", "flow_exit_seconds",
        ):
            if ob_field in params:
                ob_kwargs[ob_field] = params[ob_field]

        ob_req = OrderBookStartRequest(**ob_kwargs)

        # Set source_exchange to the exchange that has this pair for WS data
        ob_req.source_exchange = ob_source_exchange

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
            "mode": "virtual",
            "exchange": ob_source_exchange,
            "direction": direction,
        }

    # ═══════════════════════════════════════════════════════════════════
    # Trading Engine (Candle)
    # ═══════════════════════════════════════════════════════════════════
    elif signal.mapped_engine == "trading":
        from app.services.trading.models import TradingConfig as DomainTradingConfig
        from app.services.trading.models import TradingRunMode

        # Create DB run record
        db_run = DBTradingRun(
            user_id=current_user.id,
            status="running",
            mode="virtual" if is_virtual else "real",
        )
        session.add(db_run)
        await session.flush()

        # Convert LLM params
        _tf = params.get("trend_filter", "on")
        trend_filter_enabled = _tf if isinstance(_tf, bool) else (_tf == "on")
        min_confidence_val = float(params.get("min_confidence", 0.3))

        db_config = DBTradingConfig(
            run_id=db_run.id,
            pair=signal.pair,
            strategy=signal.mapped_strategy,
            leverage=params.get("leverage", 3),
            virtual_balance=params.get("balance", 10.0),
            max_trade_amount=params.get("max_trade", 5.0),
            timeframe=params.get("timeframe", "3m"),
            duration_days=max(1, int(params.get("duration", 1) / 24)),
            exchange=selected_exchange,
            stop_loss_percent=params.get("stoploss", 2.0),
            take_profit_percent=params.get("takeprofit", 5.0),
            trend_filter_enabled=trend_filter_enabled,
        )
        session.add(db_config)
        await session.commit()

        mode_enum = TradingRunMode.real if body.mode == "real" else TradingRunMode.virtual

        domain_config = DomainTradingConfig(
            mode=mode_enum,
            pair=signal.pair,
            strategy=signal.mapped_strategy,
            leverage=params.get("leverage", 3),
            virtual_balance=params.get("balance", 10.0),
            max_trade_amount=params.get("max_trade", 5.0),
            timeframe=params.get("timeframe", "3m"),
            duration_days=max(1, int(params.get("duration", 1) / 24)),
            exchange=selected_exchange,
            stop_loss_percent=params.get("stoploss", 2.0),
            take_profit_percent=params.get("takeprofit", 5.0),
            trend_filter_enabled=trend_filter_enabled,
            min_confidence=min_confidence_val,
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
            "mode": "virtual" if is_virtual else "real",
            "exchange": selected_exchange,
            "direction": direction,
        }

    else:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Неизвестный движок: {signal.mapped_engine}",
        )
