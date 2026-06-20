"""Auto-execute trading signals — start runs automatically after classification.

Architecture:
  1. SignalMapper classifies signal → saves mapped_* fields → commits
  2. This module calls POST /trading/signals/{id}/start on local API
     to start the appropriate engine in the uvicorn process (where scheduler lives)
"""

from __future__ import annotations

import json
import logging
from copy import deepcopy

import httpx

logger = logging.getLogger(__name__)

_API_BASE = "http://localhost:8000"
_API_TIMEOUT = 30  # seconds

# ── Принудительные дефолты для авто-запуска ──────────────────────────
_AUTO_BALANCE_MIN = 50.0       # минимальный баланс 50$
_AUTO_DURATION_HOURS = 0.5     # 30 минут жизни trading-движка
_AUTO_OB_STOP_HOURS = 0.5      # 30 минут жизни OB-движка


async def _ensure_auto_defaults(signal) -> None:
    """Override signal's mapped_params with forced defaults.

    Применяется перед вызовом API, чтобы все авто-запуски имели:
      - баланс >= 50$
      - время жизни 30 минут (0.5 ч)
    Сохраняет изменения в БД.
    """
    from sqlalchemy import select

    from app.core.database import async_session_factory
    from app.models.trading_signal import TradingSignal

    params = deepcopy(signal.mapped_params or {})

    # 1. Баланс: минимум 50$
    current_balance = float(params.get("balance", 0))
    params["balance"] = max(current_balance, _AUTO_BALANCE_MIN)

    # 2. Время жизни в зависимости от движка
    engine = signal.mapped_engine or ""
    if engine == "ob":
        params["auto_stop"] = _AUTO_OB_STOP_HOURS
        params["duration"] = _AUTO_OB_STOP_HOURS
    elif engine == "trading":
        params["duration"] = _AUTO_DURATION_HOURS

    # 3. Сохраняем обновлённые params в БД
    async with async_session_factory() as session:
        stmt = select(TradingSignal).where(TradingSignal.id == signal.id)
        obj = (await session.execute(stmt)).scalar_one_or_none()
        if obj is not None:
            obj.mapped_params = params
            await session.commit()

    # Обновляем локальный объект
    signal.mapped_params = params


async def _get_admin_token() -> str | None:
    """Generate a JWT access token for the admin user."""
    from uuid import UUID

    from sqlalchemy import select

    from app.core.database import async_session_factory
    from app.core.security import create_access_token
    from app.models.user import User

    async with async_session_factory() as session:
        stmt = select(User).where(User.username == "admin")
        result = await session.execute(stmt)
        admin = result.scalar_one_or_none()

    if admin is None:
        logger.error("[AutoExec] Admin user not found, cannot authenticate")
        return None

    return create_access_token(subject=str(admin.id))


async def try_auto_execute(signal_id: int) -> None:
    """Try to auto-start a run from a classified signal via local API.

    Calls POST /trading/signals/{signal_id}/start with virtual mode.
    The API endpoint handles all logic (exchange selection, run creation, scheduler).
    """
    from sqlalchemy import select

    from app.core.database import async_session_factory
    from app.models.trading_signal import TradingSignal

    async with async_session_factory() as session:
        try:
            stmt = select(TradingSignal).where(TradingSignal.id == signal_id)
            result = await session.execute(stmt)
            signal = result.scalar_one_or_none()

            if signal is None:
                logger.warning("[AutoExec] Signal #%d not found, skipping", signal_id)
                return

            # Skip if already processed
            if signal.is_processed:
                logger.info("[AutoExec] Signal #%d already processed, skipping", signal_id)
                return

            # Skip if not classified
            if not signal.mapped_engine or not signal.mapped_strategy:
                logger.info(
                    "[AutoExec] Signal #%d not yet classified (engine=%s, strategy=%s), skipping",
                    signal_id, signal.mapped_engine, signal.mapped_strategy,
                )
                return

            logger.info(
                "[AutoExec] Calling API for signal #%d (%s %s → %s/%s)",
                signal_id, signal.pair, signal.exchange,
                signal.mapped_engine, signal.mapped_strategy,
            )

            # ── Принудительные дефолты баланса и времени жизни ──────────
            await _ensure_auto_defaults(signal)

            # ── Call local API with admin auth ──────────────────────────
            token = await _get_admin_token()
            if token is None:
                logger.error("[AutoExec] Cannot authenticate, skipping signal #%d", signal_id)
                return

            async with httpx.AsyncClient(timeout=_API_TIMEOUT) as client:
                resp = await client.post(
                    f"{_API_BASE}/api/v1/trading/signals/{signal_id}/start",
                    headers={"Authorization": f"Bearer {token}"},
                    json={
                        "mode": "virtual",
                        "exchange": None,  # API auto-selects
                        "direction": None,  # API auto-selects from signal
                    },
                )

            if resp.status_code == 201:
                logger.info(
                    "[AutoExec] ✅ Signal #%d → run started: %s",
                    signal_id, resp.text,
                )
                # Mark as processed
                signal.is_processed = True
                await session.commit()
            elif resp.status_code == 429:
                logger.warning(
                    "[AutoExec] ⏸ Signal #%d: scheduler at capacity (429), deferring",
                    signal_id,
                )
            elif resp.status_code == 409:
                logger.warning(
                    "[AutoExec] ⏸ Signal #%d: conflict (real run active), deferring",
                    signal_id,
                )
            else:
                body = resp.text[:500]
                logger.warning(
                    "[AutoExec] ❌ Signal #%d: API returned %d — %s",
                    signal_id, resp.status_code, body,
                )
                # Still mark as processed to avoid retry loops on permanent errors
                signal.is_processed = True
                await session.commit()

        except httpx.ConnectError:
            logger.warning(
                "[AutoExec] ⚠ Signal #%d: backend API not reachable on :8000",
                signal_id,
            )
        except Exception as e:
            logger.exception("[AutoExec] Error processing signal #%d: %s", signal_id, e)


async def catch_up_pending_signals() -> int:
    """Scan for unprocessed classified signals and try to auto-execute them.

    Called once on daemon startup to process signals that were classified
    before the auto-execute feature was added.
    """
    from sqlalchemy import select

    from app.core.database import async_session_factory
    from app.models.trading_signal import TradingSignal

    async with async_session_factory() as session:
        stmt = (
            select(TradingSignal)
            .where(
                TradingSignal.is_processed == False,
                TradingSignal.mapped_engine.isnot(None),
                TradingSignal.mapped_strategy.isnot(None),
            )
            .order_by(TradingSignal.created_at.asc())
            .limit(50)
        )
        result = await session.execute(stmt)
        signals = result.scalars().all()

    if not signals:
        return 0

    count = 0
    for sig in signals:
        try:
            await try_auto_execute(sig.id)
            count += 1
        except Exception as e:
            logger.warning("[CatchUp] Signal #%d failed: %s", sig.id, e)

    logger.info("[CatchUp] Processed %d/%d pending signals", count, len(signals))
    return count
