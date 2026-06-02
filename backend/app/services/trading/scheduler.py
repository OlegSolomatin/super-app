"""Scheduler — manages up to 15 concurrent trading strategies.

Each scheduled run is tracked by run_id and can be started, stopped,
or queried for status. Runs are executed as asyncio tasks.
"""

from __future__ import annotations

import asyncio
import logging
import time
from datetime import datetime, timedelta, timezone
from typing import Dict, List, Optional, Tuple

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
        self._scan_progress: Dict[int, dict] = {}  # run_id -> progress info

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

                if config.mode.value == "virtual":
                    # ── Virtual live: no historical data, poll exchange ──
                    exchange_name = config.exchange or "binance"
                    if exchange_name == "binance":
                        exchange = BinanceExchange()
                    elif exchange_name == "bybit":
                        exchange = BybitExchange()
                    else:
                        exchange = MockExchange()

                    run_start = datetime.now(timezone.utc)
                    dur_sec = (config.duration_days or 30) * 86400.0
                    trades, metrics = await engine.run_virtual_live(
                        exchange,
                        start_time=run_start,
                        duration_seconds=dur_sec,
                        on_progress=lambda tr, m: None,  # progress saved via scheduler polling
                    )

                else:
                    # ── Historical/Real: load candles then run ──
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

        Cancels the asyncio task and removes it from the tracking dict.
        """
        task = self._tasks.get(run_id)
        if task is None:
            raise KeyError(f"Run {run_id} is not active or does not exist.")
        task.cancel()
        logger.info("Run %d: stop requested", run_id)

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


# Singleton scheduler instance
scheduler = TradingScheduler()
