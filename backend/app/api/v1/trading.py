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

from datetime import datetime, timezone
from typing import Optional
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.database import get_session
from app.core.dependencies import get_current_user
from app.models.trading import TradingConfig as DBTradingConfig
from app.models.trading import TradingResult as DBTradingResult
from app.models.trading import TradingRun as DBTradingRun
from app.models.trading import TradingTrade as DBTradingTrade
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
from app.services.trading.models import (
    TradingConfig as DomainTradingConfig,
    TradingRunMode,
)
from app.services.trading.scheduler import scheduler

router = APIRouter(prefix="/trading", tags=["trading"])

# ---------------------------------------------------------------------------
# Hardcoded pair list
# ---------------------------------------------------------------------------
COIN_ICON_NAMES: dict[str, str] = {
    "BTC": "bitcoin-btc",
    "ETH": "ethereum-eth",
    "BNB": "binance-coin-bnb",
    "SOL": "solana-sol",
    "XRP": "xrp-xrp",
    "ADA": "cardano-ada",
    "DOGE": "dogecoin-doge",
    "AVAX": "avalanche-avax",
    "DOT": "polkadot-dot",
    "MATIC": "polygon-matic",
    "LTC": "litecoin-ltc",
    "LINK": "chainlink-link",
    "UNI": "uniswap-uni",
    "ATOM": "cosmos-atom",
    "ETC": "ethereum-classic-etc",
    "FIL": "filecoin-fil",
    "TRX": "tron-trx",
    "XLM": "stellar-xlm",
    "VET": "vechain-vet",
    "ALGO": "algorand-algo",
    "NEAR": "near-protocol-near",
    "FTM": "fantom-ftm",
    "SAND": "the-sandbox-sand",
    "MANA": "decentraland-mana",
    "AXS": "axie-infinity-axs",
    "APE": "apecoin-ape",
    "SHIB": "shiba-inu-shib",
    "CRO": "crypto-com-cro",
    "EOS": "eos-eos",
    "ICX": "icon-icx",
    "ZEC": "zcash-zec",
    "XMR": "monero-xmr",
    "DASH": "dash-dash",
    "ZIL": "zilliqa-zil",
    "KSM": "kusama-ksm",
    "COMP": "compound-comp",
    "YFI": "yearn-finance-yfi",
    "AAVE": "aave-aave",
    "MKR": "maker-mkr",
    "BAT": "basic-attention-token-bat",
    "ENJ": "enjin-coin-enj",
    "CHZ": "chiliz-chz",
    "ONE": "harmony-one",
    "ANKR": "ankr-ankr",
    "IOST": "iost-iost",
    "WAVES": "waves-waves",
    "ONT": "ontology-ont",
    "IOTA": "miota-iota",
    "NANO": "nano-nano",
    "LSK": "lisk-lsk",
}

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
    PairInfo(symbol="LTCUSDT", base="LTC", quote="USDT", min_qty=0.01, tick_size=0.01),
    PairInfo(symbol="LINKUSDT", base="LINK", quote="USDT", min_qty=0.1, tick_size=0.001),
    PairInfo(symbol="UNIUSDT", base="UNI", quote="USDT", min_qty=0.1, tick_size=0.001),
    PairInfo(symbol="ATOMUSDT", base="ATOM", quote="USDT", min_qty=0.1, tick_size=0.001),
    PairInfo(symbol="ETCUSDT", base="ETC", quote="USDT", min_qty=0.1, tick_size=0.01),
    PairInfo(symbol="FILUSDT", base="FIL", quote="USDT", min_qty=0.1, tick_size=0.001),
    PairInfo(symbol="TRXUSDT", base="TRX", quote="USDT", min_qty=1.0, tick_size=0.00001),
    PairInfo(symbol="XLMUSDT", base="XLM", quote="USDT", min_qty=1.0, tick_size=0.00001),
    PairInfo(symbol="VETUSDT", base="VET", quote="USDT", min_qty=1.0, tick_size=0.000001),
    PairInfo(symbol="ALGOUSDT", base="ALGO", quote="USDT", min_qty=1.0, tick_size=0.001),
    PairInfo(symbol="NEARUSDT", base="NEAR", quote="USDT", min_qty=0.1, tick_size=0.001),
    PairInfo(symbol="FTMUSDT", base="FTM", quote="USDT", min_qty=0.1, tick_size=0.001),
    PairInfo(symbol="SANDUSDT", base="SAND", quote="USDT", min_qty=1.0, tick_size=0.0001),
    PairInfo(symbol="MANAUSDT", base="MANA", quote="USDT", min_qty=1.0, tick_size=0.0001),
    PairInfo(symbol="AXSUSDT", base="AXS", quote="USDT", min_qty=0.01, tick_size=0.001),
    PairInfo(symbol="APEUSDT", base="APE", quote="USDT", min_qty=0.1, tick_size=0.001),
    PairInfo(symbol="SHIBUSDT", base="SHIB", quote="USDT", min_qty=100000, tick_size=0.00000001),
    PairInfo(symbol="CROUSDT", base="CRO", quote="USDT", min_qty=1.0, tick_size=0.0001),
    PairInfo(symbol="EOSUSDT", base="EOS", quote="USDT", min_qty=0.1, tick_size=0.001),
    PairInfo(symbol="ICXUSDT", base="ICX", quote="USDT", min_qty=1.0, tick_size=0.001),
    PairInfo(symbol="ZECUSDT", base="ZEC", quote="USDT", min_qty=0.001, tick_size=0.01),
    PairInfo(symbol="XMRUSDT", base="XMR", quote="USDT", min_qty=0.001, tick_size=0.01),
    PairInfo(symbol="DASHUSDT", base="DASH", quote="USDT", min_qty=0.01, tick_size=0.01),
    PairInfo(symbol="ZILUSDT", base="ZIL", quote="USDT", min_qty=1.0, tick_size=0.00001),
    PairInfo(symbol="KSMUSDT", base="KSM", quote="USDT", min_qty=0.01, tick_size=0.01),
    PairInfo(symbol="COMPUSDT", base="COMP", quote="USDT", min_qty=0.01, tick_size=0.01),
    PairInfo(symbol="YFIUSDT", base="YFI", quote="USDT", min_qty=0.0001, tick_size=0.01),
    PairInfo(symbol="AAVEUSDT", base="AAVE", quote="USDT", min_qty=0.01, tick_size=0.01),
    PairInfo(symbol="MKRUSDT", base="MKR", quote="USDT", min_qty=0.001, tick_size=0.01),
    PairInfo(symbol="BATUSDT", base="BAT", quote="USDT", min_qty=1.0, tick_size=0.0001),
    PairInfo(symbol="ENJUSDT", base="ENJ", quote="USDT", min_qty=1.0, tick_size=0.001),
    PairInfo(symbol="CHZUSDT", base="CHZ", quote="USDT", min_qty=1.0, tick_size=0.0001),
    PairInfo(symbol="ONEUSDT", base="ONE", quote="USDT", min_qty=1.0, tick_size=0.00001),
    PairInfo(symbol="ANKRUSDT", base="ANKR", quote="USDT", min_qty=1.0, tick_size=0.00001),
    PairInfo(symbol="IOSTUSDT", base="IOST", quote="USDT", min_qty=1.0, tick_size=0.00001),
    PairInfo(symbol="WAVESUSDT", base="WAVES", quote="USDT", min_qty=0.1, tick_size=0.001),
    PairInfo(symbol="ONTUSDT", base="ONT", quote="USDT", min_qty=1.0, tick_size=0.0001),
    PairInfo(symbol="IOTAUSDT", base="IOTA", quote="USDT", min_qty=0.1, tick_size=0.001),
    PairInfo(symbol="NANOUSDT", base="NANO", quote="USDT", min_qty=0.1, tick_size=0.001),
    PairInfo(symbol="LSKUSDT", base="LSK", quote="USDT", min_qty=0.1, tick_size=0.001),
]

def _get_pair_list() -> list[dict]:
    """Build pair list with icon_url populated."""
    items = []
    for p in HARDCODED_PAIRS:
        coin_name = COIN_ICON_NAMES.get(p.base)
        icon_url = (
            f"https://cryptologos.cc/logos/{coin_name}-logo.png?v=040"
            if coin_name
            else None
        )
        items.append({
            "symbol": p.symbol,
            "base": p.base,
            "quote": p.quote,
            "min_qty": p.min_qty,
            "tick_size": p.tick_size,
            "icon_url": icon_url,
        })
    return items

# ---------------------------------------------------------------------------
# Hardcoded strategy list
# ---------------------------------------------------------------------------
HARDCODED_STRATEGIES = [
    StrategyInfo(
        name="hammer",
        description="Молот — бычий разворотный паттерн. Маленькое тело, длинная нижняя тень.",
        type="candle_pattern",
        nuances=(
            "📈 **Условия входа (BUY):**\n"
            "• Тело свечи малое (≤30% от всего диапазона)\n"
            "• Нижняя тень ≥2× тела\n"
            "• Верхняя тень малая (≤10% от диапазона)\n"
            "• Свеча находится после нисходящего тренда\n\n"
            "📉 **Условия выхода:**\n"
            "• Стоп-лосс (SL): −2% от цены входа\n"
            "• Тейк-профит (TP): +5% от цены входа\n"
            "• Либо по сигналу Inverse Hammer\n\n"
            "⚙️ **Настройки по умолчанию:**\n"
            "• SL: 2% | TP: 5% | Риск:Reward = 1:2.5\n"
            "• Плечо: 1×–10×\n"
            "• Рекомендуемый таймфрейм: 1h–4h"
        ),
    ),
    StrategyInfo(
        name="inverse_hammer",
        description="Перевёрнутый Молот — медвежий разворотный паттерн. Маленькое тело, длинная верхняя тень.",
        type="candle_pattern",
        nuances=(
            "📈 **Условия входа (SELL):**\n"
            "• Тело свечи малое (≤30% от всего диапазона)\n"
            "• Верхняя тень ≥2× тела\n"
            "• Нижняя тень малая (≤10% от диапазона)\n"
            "• Свеча находится после восходящего тренда\n\n"
            "📉 **Условия выхода:**\n"
            "• Стоп-лосс (SL): +2% от цены входа (для шорта)\n"
            "• Тейк-профит (TP): −5% от цены входа\n"
            "• Либо по сигналу Hammer\n\n"
            "⚙️ **Настройки по умолчанию:**\n"
            "• SL: 2% | TP: 5% | Риск:Reward = 1:2.5\n"
            "• Плечо: 1×–10×\n"
            "• Рекомендуемый таймфрейм: 1h–4h"
        ),
    ),
]

# ---------------------------------------------------------------------------
# Hardcoded exchange list
# ---------------------------------------------------------------------------
HARDCODED_EXCHANGES = [
    ExchangeInfo(name="binance", display_name="Binance", supports_history=True, supports_websocket=True),
    ExchangeInfo(name="bybit", display_name="Bybit", supports_history=True, supports_websocket=True),
    ExchangeInfo(name="mock", display_name="Мок (тест)", supports_history=True, supports_websocket=False),
]

# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------


@router.post("/runs/cleanup", response_model=dict)
async def cleanup_stale_runs(
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> dict:
    """Mark stale 'running' runs as 'error' (they were orphaned by a restart)."""
    stmt = (
        select(DBTradingRun)
        .where(
            DBTradingRun.user_id == current_user.id,
            DBTradingRun.status == "running",
        )
    )
    result = await session.execute(stmt)
    runs = result.scalars().all()
    count = 0
    for run in runs:
        # Consider a run stale if the scheduler doesn't know about it
        if run.id not in scheduler.get_active_run_ids():
            run.status = "error"
            run.error = "Прерван перезапуском сервера"
            run.finished_at = datetime.now(timezone.utc)
            count += 1
    await session.commit()
    return {"cleaned": count}


@router.get("/pairs", response_model=PairsListResponse)
async def list_pairs(
    search: Optional[str] = Query(None, description="Filter by symbol substring"),
    page: int = Query(1, ge=1, description="Page number"),
    page_size: int = Query(20, ge=1, le=100, description="Items per page"),
) -> PairsListResponse:
    """Return available trading pairs with optional search and pagination."""
    items = _get_pair_list()
    if search:
        search_upper = search.upper()
        items = [p for p in items if search_upper in p["symbol"].upper()]
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
    # Check scheduler capacity
    if not scheduler.can_start():
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Достигнут лимит одновременных запусков (15). Остановите активный запуск.",
        )

    # Create DB record
    db_run = DBTradingRun(
        user_id=current_user.id,
        status="running",
        mode=config.mode.value,
    )
    session.add(db_run)
    await session.flush()  # Get the run_id

    # Create config snapshot
    db_config = DBTradingConfig(
        run_id=db_run.id,
        pair=config.pair,
        strategy=config.strategy,
        leverage=config.leverage,
        virtual_balance=config.virtual_balance,
        max_trade_amount=config.max_trade_amount,
        timeframe=config.timeframe,
        period_start=config.period_start,
        period_end=config.period_end,
        duration_days=config.duration_days,
        exchange=config.exchange,
        notification_bot_id=(
            UUID(config.notification_bot_id)
            if config.notification_bot_id
            else None
        ),
    )
    session.add(db_config)

    await session.commit()

    # Eagerly load relationships before validation
    stmt = (
        select(DBTradingRun)
        .options(
            selectinload(DBTradingRun.config),
            selectinload(DBTradingRun.result),
            selectinload(DBTradingRun.trades),
        )
        .where(DBTradingRun.id == db_run.id)
    )
    result = await session.execute(stmt)
    db_run = result.scalar_one()

    # Convert to domain config for the engine
    domain_config = DomainTradingConfig(
        mode=TradingRunMode(config.mode.value),
        pair=config.pair,
        strategy=config.strategy,
        leverage=config.leverage,
        virtual_balance=config.virtual_balance,
        max_trade_amount=config.max_trade_amount,
        timeframe=config.timeframe,
        period_start=config.period_start,
        period_end=config.period_end,
        duration_days=config.duration_days,
        exchange=config.exchange,
        notification_bot_id=str(config.notification_bot_id) if config.notification_bot_id else None,
    )

    # Schedule the run (fire-and-forget via async task)
    # Scheduler creates its own DB session internally
    await scheduler.start_run(
        run_id=db_run.id,
        config=domain_config,
    )

    return TradingRunResponse.model_validate(db_run)


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
    stmt = (
        select(DBTradingRun)
        .options(selectinload(DBTradingRun.config), selectinload(DBTradingRun.result))
        .where(DBTradingRun.user_id == current_user.id)
    )
    if status_filter:
        stmt = stmt.where(DBTradingRun.status == status_filter.value)
    stmt = stmt.order_by(DBTradingRun.started_at.desc())
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
    stmt = (
        select(DBTradingRun)
        .options(selectinload(DBTradingRun.config), selectinload(DBTradingRun.result))
        .where(
            DBTradingRun.id == run_id,
            DBTradingRun.user_id == current_user.id,
        )
    )
    result = await session.execute(stmt)
    run = result.scalar_one_or_none()
    if run is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Запуск не найден.",
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
    stmt = select(DBTradingRun).where(
        DBTradingRun.id == run_id,
        DBTradingRun.user_id == current_user.id,
    )
    result = await session.execute(stmt)
    run = result.scalar_one_or_none()
    if run is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Запуск не найден.",
        )

    # Fetch trades from DB
    stmt = (
        select(DBTradingTrade)
        .where(DBTradingTrade.run_id == run_id)
        .order_by(DBTradingTrade.entry_time.desc())
        .offset((page - 1) * page_size)
        .limit(page_size)
    )
    result = await session.execute(stmt)
    db_trades = result.scalars().all()

    # Get total count
    count_stmt = select(DBTradingTrade).where(DBTradingTrade.run_id == run_id)
    count_result = await session.execute(count_stmt)
    total = len(count_result.scalars().all())

    items = [TradeResponse.model_validate(t) for t in db_trades]
    total_pages = max(1, (total + page_size - 1) // page_size)

    return TradeListResponse(
        items=items,
        total=total,
        page=page,
        page_size=page_size,
        total_pages=total_pages,
    )


@router.get("/runs/{run_id}/code")
async def get_run_strategy_code(
    run_id: int,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> dict:
    """Return the strategy code/logic used by a trading run."""
    stmt = (
        select(DBTradingRun)
        .options(selectinload(DBTradingRun.config))
        .where(
            DBTradingRun.id == run_id,
            DBTradingRun.user_id == current_user.id,
        )
    )
    result = await session.execute(stmt)
    run = result.scalar_one_or_none()
    if run is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Запуск не найден.",
        )

    strategy_name = run.config.strategy if run.config else "unknown"

    # Return the strategy description from the hardcoded list
    strategy_desc = "Неизвестная стратегия"
    for s in HARDCODED_STRATEGIES:
        if s.name == strategy_name:
            strategy_desc = s.description
            break

    return {
        "run_id": run_id,
        "strategy": strategy_name,
        "description": strategy_desc,
        "code": f"# {strategy_name} strategy\n# {strategy_desc}",
    }


@router.delete("/runs/{run_id}", status_code=status.HTTP_204_NO_CONTENT)
async def stop_run(
    run_id: int,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> None:
    """Stop and delete a trading run."""
    stmt = select(DBTradingRun).where(
        DBTradingRun.id == run_id,
        DBTradingRun.user_id == current_user.id,
    )
    result = await session.execute(stmt)
    run = result.scalar_one_or_none()
    if run is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Запуск не найден.",
        )

    # Try to stop the engine if it's running
    try:
        await scheduler.stop_run(run_id)
    except KeyError:
        pass  # Not active in scheduler, still delete from DB

    # Update status to stopped
    run.status = "stopped"
    run.finished_at = datetime.now(timezone.utc)
    await session.commit()
