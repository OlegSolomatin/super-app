"""Scheduler — manages up to 15 concurrent trading strategies.

Each scheduled run is tracked by run_id and can be started, stopped,
or queried for status. Runs are executed as asyncio tasks.
"""

from __future__ import annotations

import asyncio
import json
import logging
import time
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List, Optional, Tuple

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.database import async_session_factory
from app.models.trading import TradingConfig as DBTradingConfig
from app.models.trading import TradingResult as DBTradingResult
from app.models.trading import TradingRun as DBTradingRun
from app.models.trading import TradingTrade as DBTradingTrade
from app.services.trading.data_loader import DataLoader
from app.services.trading.engine import ALL_PAIRS_SCANNER_STRATEGIES, TradingEngine
from app.services.trading.exchange.binance import BinanceExchange
from app.services.trading.exchange.bybit import BybitExchange
from app.services.trading.exchange.mock import MockExchange
from app.services.trading.models import (
    Candle,
    Metrics,
    Trade,
    TradingConfig,
    TradingRunStatus,
)
from app.services.trading.pair_list import ALL_PAIR_SYMBOLS, fetch_all_usdt_pairs

logger = logging.getLogger(__name__)


class TradingScheduler:
    """Manages concurrent trading strategy runs (max 15).

    Each run is an asyncio.Task that loads data, runs the engine,
    and persists results to the database.
    """

    MAX_RUNS = 15

    def __init__(self) -> None:
        self._tasks: Dict[int, asyncio.Task] = {}
        self._engines: Dict[int, Any] = {}  # run_id -> OrderBookEngine (store for status)
        self._scan_progress: Dict[int, dict] = {}  # run_id -> progress info

    async def startup(self) -> None:
        """Run startup tasks: cleanup orphaned engines from DB."""
        try:
            cleaned = await self.cleanup_orphaned_engines()
            if cleaned:
                logger.info(f"[OBScheduler] Startup: cleaned {len(cleaned)} orphaned runs: {cleaned}")
        except Exception as e:
            logger.warning(f"[OBScheduler] Startup cleanup failed (non-fatal): {e}")

    def get_engine_status(self, run_id: int) -> Optional[dict]:
        """Return live status for an OB engine run, or None if not running."""
        engine = self._engines.get(run_id)
        if engine is None:
            return None
        return engine.status

    def get_scan_progress(self, run_id: int) -> Optional[dict]:
        """Return scan progress for a pair-scanner run, or None if not scanning."""
        return self._scan_progress.get(run_id)

    def _update_scan_progress(
        self,
        run_id: int,
        scanned: int,
        total: int,
        trades: int,
        pnl: float,
        current_pair: str,
        start_time: float,
    ) -> None:
        """Update in-memory scan progress with ETA calculation."""
        elapsed = time.time() - start_time
        avg_per_pair = elapsed / max(scanned, 1)
        remaining = avg_per_pair * (total - scanned)
        self._scan_progress[run_id] = {
            "status": "scanning",
            "total_pairs": total,
            "scanned_pairs": scanned,
            "trades_found": trades,
            "pnl": round(pnl, 2),
            "elapsed_seconds": round(elapsed, 1),
            "estimated_remaining_seconds": round(remaining, 1),
            "current_pair": current_pair,
        }

    def can_start(self) -> bool:
        """Return True if fewer than MAX_RUNS are active."""
        return len(self._tasks) < self.MAX_RUNS

    def get_active_count(self) -> int:
        """Return the number of currently active runs."""
        return len(self._tasks)

    def get_active_run_ids(self) -> List[int]:
        """Return list of active run IDs."""
        return list(self._tasks.keys())

    def get_active_ob_count(self) -> int:
        """Return number of active OrderBook engines."""
        from app.services.trading.orderbook.engine import OrderBookEngine
        count = 0
        for rid, engine in list(self._engines.items()):
            task = self._tasks.get(rid)
            if task is not None and not task.done():
                if isinstance(engine, OrderBookEngine):
                    count += 1
        return count

    async def start_run(
        self,
        run_id: int,
        config: TradingConfig,
    ) -> None:
        """Create and start a new trading run.

        Creates an asyncio task that:
        1. Loads candles via DataLoader
        2. Runs the engine
        3. Persists results and trades to DB
        4. Updates run status

        The scheduler creates its own database session internally,
        so the caller does not need to pass one.

        Args:
            run_id: Database ID of the trading run record.
            config: TradingConfig with strategy parameters.
        """
        if len(self._tasks) >= self.MAX_RUNS:
            raise RuntimeError("Maximum number of concurrent runs reached (15).")

        task = asyncio.create_task(
            self._execute_run(run_id, config)
        )
        self._tasks[run_id] = task
        logger.info("Started trading run %d (%s / %s)", run_id, config.strategy, config.pair)

    async def _execute_run(
        self,
        run_id: int,
        config: TradingConfig,
    ) -> None:
        """Execute a trading run: load data, run engine, save results.

        Creates its own database session to avoid conflicts with
        the caller's session.
        """
        async with async_session_factory() as session:
            try:
                # ── Resolve Telegram notification bot if configured ──
                if config.notification_bot_id:
                    try:
                        from app.models.telegram_bot import TelegramBot
                        from sqlalchemy import select

                        from uuid import UUID
                        bot_id = UUID(config.notification_bot_id) if isinstance(config.notification_bot_id, str) else config.notification_bot_id
                        stmt = select(TelegramBot).where(TelegramBot.id == bot_id)
                        result = await session.execute(stmt)
                        bot = result.scalar_one_or_none()
                        if bot:
                            config.notification_bot_token = bot.bot_token
                            config.notification_chat_id = bot.chat_id
                            logger.info("Run %d: notification bot '%s' resolved", run_id, bot.name)
                        else:
                            logger.warning("Run %d: notification_bot_id %s not found", run_id, config.notification_bot_id)
                    except Exception as e:
                        logger.warning("Run %d: failed to resolve notification bot: %s", run_id, e)

                engine = TradingEngine(config)
                logger.info(
                    "Run %d: engine created strategy=%s pair=%s min_confidence=%.3f mode=%s",
                    run_id, config.strategy, config.pair, config.min_confidence, config.mode.value,
                )

                if config.mode.value == "virtual":
                    # ── Virtual live: poll exchange with historical preload ──
                    from app.services.trading.exchange.ccxt_exchange import create_exchange
                    exchange = create_exchange(config.exchange or "binance")

                    # Preload historical candles for indicator warmup
                    preload_candles = []
                    try:
                        preload_limit = 200
                        from app.services.trading.models import Candle
                        raw_candles = await exchange.get_klines(
                            config.pair,
                            config.timeframe or "5m",
                            limit=preload_limit,
                        )
                        if raw_candles:
                            preload_candles = [
                                Candle(
                                    timestamp=c["timestamp"] if isinstance(c, dict) else c.timestamp,
                                    open=c["open"] if isinstance(c, dict) else c.open,
                                    high=c["high"] if isinstance(c, dict) else c.high,
                                    low=c["low"] if isinstance(c, dict) else c.low,
                                    close=c["close"] if isinstance(c, dict) else c.close,
                                    volume=c["volume"] if isinstance(c, dict) else c.volume,
                                )
                                for c in raw_candles
                            ]
                            logger.info(
                                "Run %d: preloaded %d candles for %s/%s",
                                run_id, len(preload_candles), config.exchange, config.pair,
                            )
                    except Exception as e:
                        logger.warning(
                            "Run %d: preload failed for %s/%s (non-fatal): %s",
                            run_id, config.exchange, config.pair, e,
                        )

                    run_start = datetime.now(timezone.utc)
                    # duration_days — это часы/24 (конвертировано из mapped_params)
                    # Для virtual режима: не дольше 6 часов
                    dur_hours = min(6, (config.duration_days or 1) * 24)
                    dur_sec = dur_hours * 3600.0
                    trades, metrics = await engine.run_virtual_live(
                        exchange,
                        start_time=run_start,
                        duration_seconds=dur_sec,
                        on_progress=lambda tr, m: None,
                        preload_candles=preload_candles or None,
                    )

                else:
                    # ── Historical/Real: load candles then run ──

                    # ── Real mode validation ─────────────────────
                    if config.mode.value == "real":
                        if not config.exchange:
                            raise ValueError("Real mode requires an exchange (e.g. 'binance')")

                        from app.models.exchange_key import ExchangeKey
                        from sqlalchemy import select as sa_select

                        # 1. Find valid API key for this exchange
                        key_stmt = sa_select(ExchangeKey).where(
                            ExchangeKey.exchange == config.exchange,
                            ExchangeKey.is_active == True,
                        ).limit(1)
                        key_result = await session.execute(key_stmt)
                        exchange_key = key_result.scalar_one_or_none()

                        if exchange_key is None:
                            raise ValueError(
                                f"No API key configured for {config.exchange}. "
                                "Add a key in Settings → API → Биржи."
                            )
                        if exchange_key.status != "valid":
                            raise ValueError(
                                f"API key for {config.exchange} is {exchange_key.status}. "
                                "Check and re-validate in Settings."
                            )

                        # 2. Check no other active real runs
                        from app.models.trading import TradingRun as DBTradingRun

                        active_real = await session.execute(
                            sa_select(DBTradingRun).where(
                                DBTradingRun.mode == "real",
                                DBTradingRun.status == "running",
                                DBTradingRun.id != run_id,
                            ).limit(1)
                        )
                        if active_real.scalar_one_or_none() is not None:
                            raise ValueError(
                                "Another real run is already active. "
                                "Max 1 real run at a time."
                            )

                        # 3. Check balance
                        from app.services.exchange.balance_checker import decrypt_key

                        api_key_plain = decrypt_key(exchange_key.api_key_encrypted)
                        api_secret_plain = decrypt_key(exchange_key.api_secret_encrypted)

                        exchange_name = config.exchange
                        from app.services.trading.exchange.ccxt_exchange import create_exchange
                        real_exchange = create_exchange(
                            exchange_name,
                            api_key=api_key_plain,
                            api_secret=api_secret_plain,
                        )

                        real_balance = await real_exchange.get_balance("USDT")
                        usdt_balance = real_balance.get("USDT", 0) if isinstance(real_balance, dict) else 0

                        needed = config.virtual_balance or config.max_trade_amount or 10
                        if usdt_balance < needed:
                            raise ValueError(
                                f"Insufficient USDT balance: ${usdt_balance:.2f}, need ${needed:.2f}. "
                                "Deposit funds or reduce trade amount."
                            )

                        logger.info(
                            "Run %d: real mode validated — %s balance=%.2f USDT, key=%s",
                            run_id, config.exchange, usdt_balance,
                            exchange_key.api_key_encrypted[:12] + "...",
                        )
                        # Pass the authenticated exchange to engine
                        config._real_exchange = real_exchange

                    # ── Candle loading ───────────────────────────
                    now = datetime.now(timezone.utc)
                    period_start = config.period_start or (now - timedelta(days=config.duration_days or 30))
                    period_end = config.period_end or now

                    # ── Pair-scanner strategies: iterate ALL pairs ──
                    if config.strategy in ALL_PAIRS_SCANNER_STRATEGIES:
                        if config.mode.value != "history":
                            raise ValueError("Pair-scanner strategies only work in history mode")

                        # Fetch dynamic pair list from Binance (cached)
                        all_pairs = await fetch_all_usdt_pairs()
                        total_pairs = len(all_pairs)
                        all_trades: List[Trade] = []
                        total_pnl = 0.0
                        scan_start = time.time()
                        logger.info(
                            "Run %d: pair-scanner %s scanning %d pairs (dynamic from Binance) [%s]",
                            run_id, config.strategy, total_pairs, config.timeframe,
                        )

                        # Init progress
                        self._scan_progress[run_id] = {
                            "status": "scanning",
                            "total_pairs": total_pairs,
                            "scanned_pairs": 0,
                            "trades_found": 0,
                            "elapsed_seconds": 0.0,
                            "estimated_remaining_seconds": 0.0,
                            "current_pair": "",
                        }

                        for idx, pair_symbol in enumerate(all_pairs):
                            try:
                                loader = DataLoader(
                                    pair=pair_symbol,
                                    timeframe=config.timeframe,
                                    exchange_name=config.exchange or "binance",
                                )
                                pair_candles = await loader.load_history(period_start, period_end)

                                if not pair_candles or len(pair_candles) < 20:
                                    # Still count as scanned for progress
                                    self._update_scan_progress(run_id, idx + 1, total_pairs, len(all_trades), total_pnl, pair_symbol, scan_start)
                                    continue

                                # Reuse engine with this pair
                                pair_config = TradingConfig(
                                    mode=config.mode,
                                    pair=pair_symbol,
                                    strategy=config.strategy,
                                    leverage=config.leverage,
                                    virtual_balance=config.virtual_balance,
                                    max_trade_amount=config.max_trade_amount,
                                    timeframe=config.timeframe,
                                    exchange=config.exchange,
                                    period_start=config.period_start,
                                    period_end=config.period_end,
                                    stop_loss_percent=config.stop_loss_percent or 1.0,
                                    take_profit_percent=config.take_profit_percent or 5.0,
                                    trend_filter_enabled=config.trend_filter_enabled,
                                    trend_filter_period=config.trend_filter_period,
                                )
                                pair_engine = TradingEngine(pair_config)
                                pair_trades, pair_metrics = await pair_engine.run_history(pair_candles)

                                # Tag each trade with its pair
                                for t in pair_trades:
                                    t.pair = pair_symbol

                                all_trades.extend(pair_trades)
                                total_pnl += pair_metrics.profit_loss

                                self._update_scan_progress(run_id, idx + 1, total_pairs, len(all_trades), total_pnl, pair_symbol, scan_start)

                            except Exception as pair_err:
                                logger.warning(
                                    "Run %d: pair %s scan error: %s", run_id, pair_symbol, pair_err,
                                )
                                self._update_scan_progress(run_id, idx + 1, total_pairs, len(all_trades), total_pnl, pair_symbol, scan_start)
                                continue

                        # Mark done
                        self._scan_progress[run_id] = {
                            "status": "done",
                            "total_pairs": total_pairs,
                            "scanned_pairs": total_pairs,
                            "trades_found": len(all_trades),
                            "elapsed_seconds": time.time() - scan_start,
                            "estimated_remaining_seconds": 0.0,
                            "current_pair": "",
                        }
                        logger.info(
                            "Run %d: scan completed %d pairs, %d trades found, PnL=%.2f",
                            run_id, total_pairs, len(all_trades), total_pnl,
                        )
                        trades = all_trades
                        metrics = Metrics(
                            total_trades=len(all_trades),
                            win_trades=sum(1 for t in all_trades if t.pnl > 0),
                            loss_trades=sum(1 for t in all_trades if t.pnl <= 0),
                            win_rate=sum(1 for t in all_trades if t.pnl > 0) / len(all_trades) if all_trades else 0.0,
                            profit_loss=total_pnl,
                            final_balance=config.virtual_balance + total_pnl,
                        )
                    else:
                        # ── Single-pair strategy (standard) ──
                        loader = DataLoader(pair=config.pair, timeframe=config.timeframe, exchange_name=config.exchange or "binance")
                        candles = await loader.load_history(period_start, period_end)

                        if not candles:
                            raise ValueError(f"No candle data available for {config.pair} ({config.timeframe})")

                        logger.info(
                            "Run %d: loaded %d candles for %s [%s]",
                            run_id,
                            len(candles),
                            config.pair,
                            config.timeframe,
                        )

                        if config.mode.value == "real":
                            trades, metrics = await engine.run_real(candles)
                        else:
                            trades, metrics = await engine.run_history(candles)

                logger.info(
                    "Run %d: completed with %d trades, PnL=%.2f",
                    run_id,
                    metrics.total_trades,
                    metrics.profit_loss,
                )

                # 3. Persist results to DB
                await self._save_results(
                    run_id=run_id,
                    config=config,
                    trades=trades,
                    metrics=metrics,
                    session=session,
                    status="done",
                    error=None,
                )

            except asyncio.CancelledError:
                logger.info("Run %d: cancelled", run_id)
                # Save partial state with stopped status
                try:
                    await self._save_results(
                        run_id=run_id,
                        config=config,
                        trades=[],
                        metrics=Metrics(),
                        session=session,
                        status="stopped",
                        error="Cancelled by user",
                    )
                except Exception:
                    logger.exception("Run %d: error saving cancelled state", run_id)
                raise

            except Exception as exc:
                logger.exception("Run %d: error during execution", run_id)
                try:
                    await self._save_results(
                        run_id=run_id,
                        config=config,
                        trades=[],
                        metrics=Metrics(),
                        session=session,
                        status="error",
                        error=str(exc),
                    )
                except Exception:
                    logger.exception("Run %d: error saving error state", run_id)

            finally:
                self._tasks.pop(run_id, None)
                self._scan_progress.pop(run_id, None)

    async def _save_results(
        self,
        run_id: int,
        config: TradingConfig,
        trades: List[Trade],
        metrics: Metrics,
        session: AsyncSession,
        status: str,
        error: Optional[str],
    ) -> None:
        """Save run results to database."""
        # Reload the run with config relationship loaded
        stmt = (
            select(DBTradingRun)
            .options(
                selectinload(DBTradingRun.config),
                selectinload(DBTradingRun.result),
                selectinload(DBTradingRun.trades),
            )
            .where(DBTradingRun.id == run_id)
        )
        result = await session.execute(stmt)
        db_run = result.scalar_one_or_none()
        if db_run is None:
            logger.warning("Run %d: not found in DB, skipping save", run_id)
            return

        db_run.status = status
        db_run.finished_at = datetime.now(timezone.utc)
        db_run.error = error

        # Save config snapshot (update existing)
        if db_run.config:
            db_run.config.pair = config.pair
            db_run.config.strategy = config.strategy
            db_run.config.leverage = config.leverage
            db_run.config.virtual_balance = config.virtual_balance
            db_run.config.max_trade_amount = config.max_trade_amount
            db_run.config.timeframe = config.timeframe
            db_run.config.period_start = config.period_start
            db_run.config.period_end = config.period_end
            db_run.config.duration_days = config.duration_days
            db_run.config.exchange = config.exchange
            db_run.config.stop_loss_percent = config.stop_loss_percent
            db_run.config.take_profit_percent = config.take_profit_percent

        # Save result
        if db_run.result is None:
            db_run.result = DBTradingResult(run_id=run_id)
        db_run.result.total_trades = metrics.total_trades
        db_run.result.win_trades = metrics.win_trades
        db_run.result.loss_trades = metrics.loss_trades
        db_run.result.win_rate = metrics.win_rate
        db_run.result.profit_loss = metrics.profit_loss
        db_run.result.final_balance = metrics.final_balance
        db_run.result.max_drawdown = metrics.max_drawdown

        # Save trades
        # Clear old trades and add new ones
        if hasattr(db_run, 'trades') and db_run.trades:
            for t in db_run.trades:
                await session.delete(t)

        for trade in trades:
            db_trade = DBTradingTrade(
                run_id=run_id,
                side=trade.side,
                pair=trade.pair,  # might be None for non-scanner runs
                entry_price=trade.entry_price,
                exit_price=trade.exit_price,
                entry_time=trade.entry_time or datetime.now(timezone.utc),
                exit_time=trade.exit_time,
                quantity=trade.quantity,
                pnl=trade.pnl,
                pnl_percent=(
                    (trade.pnl / (trade.entry_price * trade.quantity)) * 100
                    if trade.entry_price and trade.quantity > 0
                    else 0.0
                ),
                status="closed" if trade.exit_price is not None else "open",
            )
            session.add(db_trade)

        await session.commit()
        logger.info("Run %d: results saved (%d trades)", run_id, len(trades))

    async def stop_run(self, run_id: int) -> None:
        """Stop a running strategy by run_id.

        Cancels the asyncio task, stops the engine, and updates DB status.
        Handles orphaned runs (in DB as running but lost from scheduler state).
        """
        from datetime import datetime, timezone
        from sqlalchemy import update
        from app.core.database import async_session_factory
        from app.models.trading import OrderBookRun as DBOrderBookRun

        task = self._tasks.pop(run_id, None)
        if task:
            task.cancel()
            logger.info("Run %d: stop requested (task cancelled)", run_id)
        else:
            logger.warning("Run %d: no active task found, checking DB/engine", run_id)

        # Always try to stop the engine if present
        engine = self._engines.pop(run_id, None)
        if engine:
            try:
                await engine.stop()
                logger.info("Run %d: engine stopped", run_id)
            except Exception as e:
                logger.warning(f"Run {run_id}: engine.stop() failed: {e}")

        # Update DB status to cancelled regardless of engine/task state
        try:
            async with async_session_factory() as session:
                await session.execute(
                    update(DBOrderBookRun)
                    .where(DBOrderBookRun.id == run_id)
                    .values(
                        status="cancelled",
                        finished_at=datetime.now(timezone.utc),
                    )
                )
                await session.commit()
                logger.info("Run %d: DB status set to cancelled", run_id)
        except Exception as e:
            logger.warning(f"Run {run_id}: failed to update DB status: {e}")

    async def get_status(self, run_id: int) -> Optional[str]:
        """Return current status of a run, or None if not found."""
        task = self._tasks.get(run_id)
        if task is None:
            return None
        if task.cancelled():
            return "stopped"
        if task.done():
            if task.exception():
                return "error"
            return "done"
        return "running"

    async def list_runs(self) -> Dict[int, str]:
        """Return a mapping of run_id -> status for all active runs."""
        return {rid: (await self.get_status(rid) or "unknown") for rid in self._tasks}

    async def cleanup_orphaned_engines(self) -> list[dict]:
        """Find and stop orphaned OB engines, return summary of cleaned runs.

        Orphaned = engines still running in event loop but lost from scheduler tracking.
        """
        cleaned = []
        # Scan any running db runs not in _tasks/_engines
        from app.core.database import async_session_factory
        from sqlalchemy import select
        from app.models.trading import OrderBookRun as DBOrderBookRun

        async with async_session_factory() as session:
            stmt = select(DBOrderBookRun).where(DBOrderBookRun.status == "running")
            result = await session.execute(stmt)
            for db_run in result.scalars().all():
                run_id = db_run.id
                engine = self._engines.get(run_id)
                if engine:
                    # Active engine — stop it
                    try:
                        await engine.stop()
                    except Exception as e:
                        logger.warning(f"Cleanup: engine stop failed for run {run_id}: {e}")
                    self._engines.pop(run_id, None)
                    self._tasks.pop(run_id, None)
                    cleaned.append({"id": run_id, "action": "stopped"})
                else:
                    # Ghost run in DB but no engine — mark as error
                    from sqlalchemy import update
                    from datetime import datetime, timezone
                    await session.execute(
                        update(DBOrderBookRun)
                        .where(DBOrderBookRun.id == run_id)
                        .values(
                            status="error",
                            finished_at=datetime.now(timezone.utc),
                            error="Cleanup: engine lost, marked as orphaned",
                        )
                    )
                    cleaned.append({"id": run_id, "action": "marked_error"})
            await session.commit()
        return cleaned

    async def start_orderbook_run(
        self,
        run_id: int,
        config: dict,  # OrderBookStartRequest as dict
    ) -> None:
        """Start an Order Book engine run as an asyncio task.

        Creates OrderBookConfig + Engine, starts it, and tracks the task.
        The engine creates its own WS stream internally.
        """
        from app.services.trading.orderbook.engine import OrderBookEngine
        from app.services.trading.orderbook.models import OrderBookConfig

        # Remove None values — they would override dataclass defaults
        clean_config = {k: v for k, v in config.items() if v is not None}

        ob_config = OrderBookConfig(
            pairs=[config.get("pair", "BTCUSDT")],
            strategy_name=config.get("strategy", "imbalance_scalping"),
            initial_balance=config.get("initial_balance", 1000.0),
            max_open_trades=config.get("max_open_trades", 1),
            source_exchange=config.get("source_exchange", "binance"),
            trade_exchange=config.get("trade_exchange", "binance"),
            mode=config.get("mode", "virtual"),
            run_id=run_id,
            imbalance_threshold=clean_config.get("imbalance_threshold", 0.65),
            surge_pct=clean_config.get("surge_pct", 20.0),
            confirmation_ticks=config.get("confirmation_ticks", 1),
            max_spread_pct=config.get("max_spread", 5.0),
            exit_after_seconds=config.get("exit_after_seconds", 60),
            max_hold_seconds=config.get("max_hold_seconds", 120),
            stoploss=config.get("stoploss", -1.0),
            trailing_stop=True,
            trailing_stop_positive=config.get("trailing_stop", 0.3),
            trailing_stop_positive_offset=config.get("trailing_offset", 0.5),
            cooldown_seconds=config.get("cooldown_seconds", 10),
            max_runtime_hours=config.get("auto_stop_hours", 0),
            # Spread Capture params
            min_spread_pct=clean_config.get("min_spread_pct", 0.02),
            spread_entry_threshold=clean_config.get("spread_entry_threshold", 0.03),
            spread_exit_threshold=clean_config.get("spread_exit_threshold", 0.01),
            # Order Flow Momentum params
            flow_threshold_volume=clean_config.get("flow_threshold_volume", 10000.0),
            min_flow_signals=clean_config.get("min_flow_signals", 2),
            flow_exit_seconds=clean_config.get("flow_exit_seconds", 30),
            # ЕРШ Scalping params
            ers_min_imbalance=clean_config.get("ers_min_imbalance", 0.52),
            ers_min_profit_pct=clean_config.get("ers_min_profit_pct", 0.01),
            ers_exit_on_reversion=clean_config.get("ers_exit_on_reversion", True),
            ers_max_hold_seconds=clean_config.get("ers_max_hold_seconds", 15),
            ers_min_volume=clean_config.get("ers_min_volume", 0.0),
            # Iceberg Detection params
            iceberg_ratio=clean_config.get("iceberg_ratio", 3.0),
            lookback_ticks=clean_config.get("lookback_ticks", 5),
            min_volume_btc=clean_config.get("min_volume_btc", 0.5),
        )

        # Real mode: создаём ExchangeExecutor
        mode = config.get("mode", "virtual")
        executor = None
        if mode == "real":
            from app.services.trading.orderbook.execution.router import (
                ExchangeExecutor,
            )
            trade_exchange = config.get("trade_exchange", "binance")
            executor = ExchangeExecutor(trade_exchange=trade_exchange)
            logger.info(
                f"[Scheduler] Real mode for run {run_id}: "
                f"trading on {trade_exchange}"
            )

        engine = OrderBookEngine(ob_config, executor=executor)
        self._engines[run_id] = engine

        task = asyncio.create_task(self._run_orderbook_engine(run_id, engine, ob_config))
        self._tasks[run_id] = task

    async def _run_orderbook_engine(
        self,
        run_id: int,
        engine,
        ob_config=None,
    ) -> None:
        """Execute OrderBook engine and persist results."""
        from datetime import datetime, timezone, timedelta
        from sqlalchemy import select

        from app.core.database import async_session_factory
        from app.models.trading import OrderBookRun as DBOrderBookRun

        live_task = None
        cancelled = False
        error_msg: str | None = None
        try:
            await engine.start()
            # ── Фоновая задача: live-статус каждые 3 сек ──────────
            async def _live_status_loop():
                while True:
                    await asyncio.sleep(3)
                    try:
                        await self._save_ob_live_status(run_id, engine)
                    except Exception as e_live:
                        logger.warning(f"[OBScheduler] Live status write failed for run {run_id}: {e_live}")

            live_task = asyncio.create_task(_live_status_loop())
            # ── Auto-stop timer ──────────────────────────────────
            if ob_config and ob_config.max_runtime_hours > 0:
                timeout = ob_config.max_runtime_hours * 3600
                logger.info(
                    f"[OBScheduler] Run {run_id} will auto-stop after "
                    f"{ob_config.max_runtime_hours}h"
                )
                try:
                    if engine._manage_task is not None:
                        await asyncio.wait_for(engine._manage_task, timeout=timeout)
                except asyncio.TimeoutError:
                    logger.info(f"[OBScheduler] Run {run_id} auto-stop after {ob_config.max_runtime_hours}h")
                    await engine.stop()
            else:
                # Engine runs until stopped or error
                if engine._manage_task is not None:
                    await engine._manage_task
        except asyncio.CancelledError:
            cancelled = True
            error_msg = "Stopped by user"
            logger.info(f"[OBScheduler] Run {run_id} cancelled, stopping engine...")
            await engine.stop()
        except Exception as e:
            error_msg = f"Engine crashed: {e}"
            logger.exception(f"[OBScheduler] Run {run_id} failed: {e}")
        finally:
            # ── Guarded cleanup: stop live loop, stop engine, clean scheduler state ──
            if live_task is not None:
                live_task.cancel()
            try:
                await engine.stop()
            except Exception:
                logger.exception(f"[OBScheduler] Run {run_id}: engine.stop() failed")
            self._engines.pop(run_id, None)
            self._tasks.pop(run_id, None)

        # Save final results to DB
        status = "cancelled" if cancelled else ("error" if error_msg else "done")
        await self._save_ob_results(
            run_id, engine, status=status,
            error_msg=error_msg,
        )

    async def _save_ob_live_status(
        self, run_id: int, engine
    ) -> None:
        """Сохранить live-статус OrderBook engine в БД (каждые 3 сек)."""
        import json
        from datetime import datetime, timezone
        from sqlalchemy import select, update

        from app.core.database import async_session_factory
        from app.models.trading import OrderBookRun as DBOrderBookRun

        wallets = getattr(engine, "wallets", None)
        if wallets is None:
            return
        current_balance = wallets.total_balance

        # Кэш для real-time PnL
        cache = getattr(engine, "cache", None)
        snap = cache.latest() if cache else None

        # Текущая открытая позиция
        trades = getattr(engine, "_trades", {})
        open_trade = None
        for pair, trade in trades.items():
            open_trade = {
                "pair": trade.pair,
                "side": trade.side,
                "entry_price": trade.entry_price,
                "quantity": trade.amount if hasattr(trade, "amount") else trade.stake_amount,
                "stake_amount": trade.stake_amount,
                "pnl": trade.current_profit(snap.mid_price) / 100 * trade.stake_amount if snap else trade.pnl,
                "pnl_pct": trade.current_profit(snap.mid_price) if snap else trade.pnl_pct,
                "entry_time": trade.entry_time.isoformat() if trade.entry_time else None,
                "age_seconds": trade.age_seconds() if hasattr(trade, "age_seconds") else 0,
            }
            break  # только первая открытая позиция

        async with async_session_factory() as session:
            # Signal metrics from engine
            metrics = getattr(engine, "metrics", {}) or {}
            signals_total = metrics.get("signals_generated", 0)
            signals_rejected = metrics.get("signals_rejected", 0)
            spm = metrics.get("signals_per_minute", 0.0)

            # Summary of rejection breakdown (top-5 reasons)
            rejection_keys = [
                "cache_not_warm", "global_stop_filtered",
                "pairlock_filtered", "has_position_filtered",
                "rejected_spread", "rejected_iceberg",
                "rejected_confirm_ticks", "rejected_no_signal",
                "rejected_gatekeeper", "rejected_wallet",
            ]
            signal_summary = {
                k: metrics.get(k, 0) for k in rejection_keys
                if metrics.get(k, 0) > 0
            }

            # Last signal info
            signal_history = getattr(engine, "_signal_history", [])
            last_signal = list(signal_history)[-1] if signal_history else None

            await session.execute(
                update(DBOrderBookRun)
                .where(DBOrderBookRun.id == run_id)
                .values(
                    current_balance=current_balance,
                    open_trade_json=json.dumps(open_trade) if open_trade else None,
                    signals_total=signals_total,
                    signals_rejected=signals_rejected,
                    signals_per_minute=spm,
                    last_heartbeat_at=datetime.now(timezone.utc),
                    last_signal_at=last_signal.get("timestamp") if last_signal else None,
                    last_signal_type=last_signal.get("signal_type") if last_signal else None,
                    last_rejection_reason=last_signal.get("detail") if last_signal and last_signal.get("status") == "filtered" else None,
                    signal_summary_json=json.dumps(signal_summary) if signal_summary else None,
                )
            )
            await session.commit()

    async def _save_ob_results(
        self, run_id: int, engine, status: str = "done", error_msg: str | None = None
    ) -> None:
        """Сохранить метрики и трейды OrderBook engine в БД."""
        from datetime import datetime, timezone
        from sqlalchemy import select, update

        from app.core.database import async_session_factory
        from app.models.trading import OrderBookRun as DBOrderBookRun

        metrics = getattr(engine, "metrics", {})
        trade_history = getattr(engine, "_trade_history", [])
        total_pnl = metrics.get("total_pnl", 0.0)

        # Сериализуем трейды для сохранения
        trades_json = []
        for t in trade_history:
            trades_json.append({
                "pair": t.pair,
                "side": t.side,
                "entry_price": t.entry_price,
                "exit_price": t.exit_price,
                "pnl": t.pnl,
                "pnl_pct": t.pnl_pct,
                "exit_type": t.exit_type,
                "exit_reason": t.exit_reason,
            })

        async with async_session_factory() as session:
            await session.execute(
                update(DBOrderBookRun)
                .where(DBOrderBookRun.id == run_id)
                .values(
                    status=status,
                    finished_at=datetime.now(timezone.utc),
                    error=error_msg,
                    metrics_json=json.dumps(metrics),
                    total_pnl=total_pnl,
                    total_trades=len(trade_history),
                    win_trades=metrics.get("win_count", 0),
                    loss_trades=metrics.get("loss_count", 0),
                    final_balance=metrics.get("peak_balance", 0.0),
                    closed_trades_json=json.dumps(trades_json) if trades_json else None,
                )
            )
            await session.commit()


# Singleton scheduler instance
scheduler = TradingScheduler()
