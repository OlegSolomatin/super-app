"""Trading engine — orchestrates the strategy execution loop.

Runs a strategy against historical or live data, manages positions,
and collects performance metrics.
"""

from __future__ import annotations

import asyncio
import logging
import math
from datetime import datetime, timedelta, timezone
from typing import Callable, List, Optional, Tuple

from app.services.trading.exchange.base import AbstractExchange
from app.services.trading.models import (
    Candle,
    Metrics,
    Signal,
    Trade,
    TradingConfig,
    TradingRun,
    TradingRunMode,
    TradingRunStatus,
)
from app.services.trading.strategies import (
    AbstractStrategy,
    HammerStrategy,
    InverseHammerStrategy,
)
from app.services.notification_service import send_telegram_notification

logger = logging.getLogger(__name__)

# Registry of available strategies
STRATEGY_REGISTRY: dict[str, type[AbstractStrategy]] = {
    "hammer": HammerStrategy,
    "inverse_hammer": InverseHammerStrategy,
}


class TradingEngine:
    """Strategy execution engine.

    Responsibilities:
    - Fetch candles via data loader
    - Compute indicators
    - Feed candles into strategy
    - Execute signals (or log them)
    - Track trades and compute metrics
    """

    def __init__(self, config: TradingConfig) -> None:
        self.config = config
        self.run = TradingRun(config=config)

    async def _notify_trade_closed(self, trade: Trade, exit_reason: str) -> None:
        """Fire-and-forget Telegram notification for a closed trade.

        Only sends if the config has bot_token and chat_id resolved.
        """
        token = self.config.notification_bot_token
        chat_id = self.config.notification_chat_id
        if not token or not chat_id:
            return

        # Compute pnl percent
        pnl_pct = (
            (trade.pnl / (trade.entry_price * trade.quantity)) * 100
            if trade.entry_price and trade.quantity > 0
            else 0.0
        )
        pnl_sign = "+" if trade.pnl >= 0 else ""
        status_emoji = "✅" if trade.pnl >= 0 else "❌"
        reason_map = {
            "stop_loss": "🛑 стоп-лосс",
            "take_profit": "🎯 тейк-профит",
            "signal": "📈 сигнал стратегии",
        }
        reason_label = reason_map.get(exit_reason, exit_reason)

        message = (
            f"{status_emoji} <b>Сделка закрыта</b>\n"
            f"Пара: {self.config.pair}\n"
            f"Сторона: {trade.side}\n"
            f"Вход: {trade.entry_price}\n"
            f"Выход: {trade.exit_price or '—'}\n"
            f"PnL: {pnl_sign}{trade.pnl:.2f} ({pnl_sign}{pnl_pct:.2f}%)\n"
            f"Статус: {reason_label}\n"
            f"Стратегия: {self.config.strategy}"
        )

        asyncio.create_task(send_telegram_notification(token, chat_id, message))

    async def run_history(self, candles: List[Candle]) -> Tuple[List[Trade], Metrics]:
        """Run strategy against historical data — instant execution."""
        return await self._execute(candles)

    @staticmethod
    def _poll_interval(timeframe: str) -> float:
        """Return polling interval in seconds for a given timeframe.

        Polls frequently enough to catch new candles within seconds of close.
        For 30m → 15s, 1h → 30s, 1d → 60s, etc.
        """
        tf_map = {
            "1m": 5, "3m": 10, "5m": 10, "15m": 15, "30m": 15,
            "1h": 30, "2h": 30, "4h": 45, "6h": 45,
            "12h": 60, "1d": 60, "1w": 120, "1M": 300,
        }
        return float(tf_map.get(timeframe, 30))

    async def run_virtual_live(
        self,
        exchange: AbstractExchange,
        start_time: Optional[datetime] = None,
        duration_seconds: Optional[float] = None,
        on_progress: Optional[Callable[[List[Trade], Metrics], None]] = None,
    ) -> Tuple[List[Trade], Metrics]:
        """Virtual live trading — polls exchange for new candles in real time.

        Does NOT load historical candles. Instead:
        1. Every N seconds, fetches the latest candle from exchange
        2. When a new completed candle arrives — analyses it
        3. Enters/exits trades based on strategy signals
        4. Runs until duration_seconds elapses or cancelled

        Args:
            exchange: Exchange connector to poll for live data.
            start_time: When the run started (for timeout + progress).
            duration_seconds: Max run duration in seconds (from duration_days).
            on_progress: Optional callback to save intermediate state.

        Returns:
            (trades, metrics) when finished or cancelled.
        """
        return await self._execute_virtual_live(exchange, start_time, duration_seconds, on_progress)

    async def run_real(self, candles: List[Candle]) -> Tuple[List[Trade], Metrics]:
        """Run strategy with real data (same logic for now — no exchange orders)."""
        return await self._execute(candles)

    @staticmethod
    def _candle_delay(candles: List[Candle], index: int) -> float:
        """Calculate delay in seconds between candle[i-1] and candle[i]."""
        if index < 1:
            return 0.0
        prev = candles[index - 1].timestamp
        curr = candles[index].timestamp
        # Ensure both are timezone-aware
        if prev.tzinfo is None:
            prev = prev.replace(tzinfo=timezone.utc)
        if curr.tzinfo is None:
            curr = curr.replace(tzinfo=timezone.utc)
        delta = (curr - prev).total_seconds()
        return max(0.0, delta)

    async def _execute_virtual_live(
        self,
        exchange: AbstractExchange,
        start_time: Optional[datetime] = None,
        duration_seconds: Optional[float] = None,
        on_progress: Optional[Callable[[List[Trade], Metrics], None]] = None,
    ) -> Tuple[List[Trade], Metrics]:
        """Live paper trading core — polls exchange for new completed candles.

        Architecture:
        - Tracks last processed candle close time
        - Every N seconds, fetches latest kline from exchange
        - When a new completed candle is detected (its close time < now):
          - Analyzes it via strategy
          - Checks entry/exit, SL/TP
          - Updates balance
        - Runs until duration_seconds elapses or cancelled (CancelledError)
        - Calls on_progress periodically with progress % and state
        - On completion/cancellation, returns all accumulated trades and metrics
        """
        # 1. Select strategy
        strategy_cls = STRATEGY_REGISTRY.get(self.config.strategy)
        if strategy_cls is None:
            raise ValueError(f"Unknown strategy: {self.config.strategy}")
        strategy = strategy_cls()

        # 2. State
        open_trade: Optional[Trade] = None
        trades: List[Trade] = []
        balance = self.config.virtual_balance
        peak_balance = balance
        max_drawdown = 0.0
        max_trade_amount = self.config.max_trade_amount
        leverage = self.config.leverage

        poll_interval = self._poll_interval(self.config.timeframe)
        last_processed: Optional[datetime] = None
        warmup_candles: List[Candle] = []
        run_start = start_time or datetime.now(timezone.utc)
        last_progress_call: float = 0.0

        logger.info(
            "Virtual live: starting for %s %s, poll every %.0fs, balance=$%.0f, duration=%.0fs",
            self.config.pair, self.config.timeframe,
            poll_interval, balance,
            duration_seconds or float("inf"),
        )

        try:
            while True:
                # ── Check timeout ──
                now = datetime.now(timezone.utc)
                if duration_seconds is not None:
                    elapsed = (now - run_start).total_seconds()
                    if elapsed >= duration_seconds:
                        logger.info(
                            "Virtual live: timeout after %.0fs (limit %.0fs)",
                            elapsed, duration_seconds,
                        )
                        break

                # ── Compute progress & notify ──
                if duration_seconds and duration_seconds > 0:
                    progress_pct = min(100.0, (elapsed / duration_seconds) * 100.0)
                else:
                    progress_pct = 0.0

                # Call on_progress at most once per 30s to avoid DB spam
                if on_progress and (progress_pct - last_progress_call >= 2.0 or progress_pct >= 99.9):
                    last_progress_call = progress_pct
                    win = sum(1 for t in trades if t.pnl and t.pnl > 0)
                    loss = sum(1 for t in trades if t.pnl and t.pnl <= 0)
                    metrics = Metrics(
                        total_trades=len(trades),
                        win_trades=win,
                        loss_trades=loss,
                        win_rate=win / len(trades) if trades else 0.0,
                        profit_loss=sum((t.pnl or 0.0) for t in trades),
                        final_balance=balance,
                        max_drawdown=max_drawdown,
                        progress=progress_pct,
                    )
                    on_progress(trades, metrics)

                # ── Fetch latest candle ──
                try:
                    candles = await exchange.get_klines(
                        pair=self.config.pair,
                        timeframe=self.config.timeframe,
                        limit=2,  # Last 2 candles
                    )
                except Exception as e:
                    logger.warning("Virtual live: poll error %s, retrying in %ds", e, poll_interval)
                    await asyncio.sleep(poll_interval)
                    continue

                if not candles:
                    await asyncio.sleep(poll_interval)
                    continue

                latest = candles[-1]

                # Check if this candle is completed (its close time has passed)
                now = datetime.now(timezone.utc)
                tf_seconds = self._candle_delay(candles, len(candles) - 1) if len(candles) >= 2 else 1800
                if tf_seconds <= 0:
                    tf_seconds = 1800  # fallback 30 min

                candle_close_time = latest.timestamp + timedelta(seconds=tf_seconds)

                # Skip if candle is still forming or already processed
                if candle_close_time > now:
                    await asyncio.sleep(poll_interval)
                    continue

                if last_processed and latest.timestamp <= last_processed:
                    await asyncio.sleep(poll_interval)
                    continue

                # Mark this candle as processed
                last_processed = latest.timestamp

                # Rebuild window: keep last 50 candles for indicator calc
                warmup_candles.append(latest)
                if len(warmup_candles) > 50:
                    warmup_candles = warmup_candles[-50:]

                # Need at least 3 candles for strategy to work
                if len(warmup_candles) < 3:
                    await asyncio.sleep(poll_interval)
                    continue

                logger.debug(
                    "Virtual live: new candle %s close=%.2f balance=$%.0f",
                    latest.timestamp, latest.close, balance,
                )

                window = warmup_candles[:]  # Full window for strategy

                # ── Check open trade ──
                if open_trade is not None:
                    should_close = False
                    exit_price = latest.close
                    exit_reason = "signal"

                    if open_trade.side == "BUY":
                        sl_price = open_trade.entry_price * (1 - self.config.stop_loss_percent / 100.0) if self.config.stop_loss_percent else None
                        tp_price = open_trade.entry_price * (1 + self.config.take_profit_percent / 100.0) if self.config.take_profit_percent else None

                        if sl_price and latest.low <= sl_price:
                            should_close = True
                            exit_price = sl_price
                            exit_reason = "stop_loss"
                        elif tp_price and latest.high >= tp_price:
                            should_close = True
                            exit_price = tp_price
                            exit_reason = "take_profit"
                    else:
                        sl_price = open_trade.entry_price * (1 + self.config.stop_loss_percent / 100.0) if self.config.stop_loss_percent else None
                        tp_price = open_trade.entry_price * (1 - self.config.take_profit_percent / 100.0) if self.config.take_profit_percent else None

                        if sl_price and latest.high >= sl_price:
                            should_close = True
                            exit_price = sl_price
                            exit_reason = "stop_loss"
                        elif tp_price and latest.low <= tp_price:
                            should_close = True
                            exit_price = tp_price
                            exit_reason = "take_profit"

                    if not should_close:
                        signals = await strategy.analyze(window)
                        for sig in signals:
                            if sig.type == "exit" and sig.side != open_trade.side:
                                should_close = True
                                exit_price = sig.price
                                exit_reason = "signal"
                                break

                    if should_close:
                        close_val = exit_price * open_trade.quantity * leverage
                        trade_pnl = close_val - (open_trade.entry_price * open_trade.quantity * leverage)
                        if open_trade.side == "SELL":
                            trade_pnl = -trade_pnl

                        open_trade.exit_price = exit_price
                        open_trade.exit_time = latest.timestamp
                        open_trade.pnl = trade_pnl
                        open_trade.exit_reason = exit_reason
                        trades.append(open_trade)
                        balance += trade_pnl
                        peak_balance = max(peak_balance, balance)
                        dd = (peak_balance - balance) / peak_balance * 100 if peak_balance > 0 else 0
                        max_drawdown = max(max_drawdown, dd)
                        open_trade = None

                        # Send notification (fire-and-forget)
                        await self._notify_trade_closed(trades[-1], exit_reason)

                        if on_progress:
                            metrics = Metrics(
                                total_trades=len(trades),
                                win_trades=sum(1 for t in trades if t.pnl and t.pnl > 0),
                                loss_trades=sum(1 for t in trades if t.pnl and t.pnl <= 0),
                                win_rate=sum(1 for t in trades if t.pnl and t.pnl > 0) / len(trades) if trades else 0.0,
                                profit_loss=sum((t.pnl or 0.0) for t in trades),
                                final_balance=balance,
                                max_drawdown=max_drawdown,
                            )
                            on_progress(trades, metrics)

                # ── Check entry ──
                if open_trade is None:
                    signals = await strategy.analyze(window)
                    for sig in signals:
                        if sig.type == "entry":
                            quantity = min(max_trade_amount / sig.price, balance * 0.5 / sig.price) if sig.price > 0 else 0
                            if quantity > 0:
                                open_trade = Trade(
                                    side=sig.side,
                                    entry_price=sig.price,
                                    entry_time=latest.timestamp,
                                    quantity=quantity,
                                )
                                logger.info(
                                    "Virtual live: ENTRY %s %s at %.2f qty=%.4f",
                                    sig.side, self.config.pair, sig.price, quantity,
                                )
                                break

                await asyncio.sleep(poll_interval)

        except asyncio.CancelledError:
            logger.info("Virtual live: cancelled after %d trades", len(trades))
            # Close any open position at market
            if open_trade is not None and trades:
                last_price = trades[-1].exit_price or trades[-1].entry_price
                close_val = last_price * open_trade.quantity * leverage
                trade_pnl = close_val - (open_trade.entry_price * open_trade.quantity * leverage)
                if open_trade.side == "SELL":
                    trade_pnl = -trade_pnl
                open_trade.exit_price = last_price
                open_trade.exit_time = datetime.now(timezone.utc)
                open_trade.pnl = trade_pnl
                open_trade.exit_reason = "cancel"
                trades.append(open_trade)
                balance += trade_pnl

                # Send notification (fire-and-forget)
                await self._notify_trade_closed(open_trade, "cancel")
                open_trade = None

        # Compute final metrics
        win_trades = sum(1 for t in trades if t.pnl and t.pnl > 0)
        loss_trades = sum(1 for t in trades if t.pnl and t.pnl <= 0)
        total_pnl = sum((t.pnl or 0.0) for t in trades)
        metrics = Metrics(
            total_trades=len(trades),
            win_trades=win_trades,
            loss_trades=loss_trades,
            win_rate=win_trades / len(trades) if trades else 0.0,
            profit_loss=total_pnl,
            final_balance=balance,
            max_drawdown=max_drawdown,
        )
        logger.info(
            "Virtual live: finished with %d trades, PnL=$%.2f, balance=$%.0f",
            len(trades), total_pnl, balance,
        )
        return trades, metrics

    async def _execute(self, candles: List[Candle]) -> Tuple[List[Trade], Metrics]:
        """Core strategy execution loop.

        1. Select the strategy
        2. Iterate candles
        3. On each candle: check entry/exit signals, SL, TP
        4. Close all positions at the end
        5. Compute metrics
        """
        if not candles:
            return [], Metrics()

        # 1. Select strategy
        strategy_cls = STRATEGY_REGISTRY.get(self.config.strategy)
        if strategy_cls is None:
            raise ValueError(f"Unknown strategy: {self.config.strategy}")
        strategy = strategy_cls()

        # 2. State
        open_trade: Optional[Trade] = None
        trades: List[Trade] = []
        balance = self.config.virtual_balance
        peak_balance = balance
        max_drawdown = 0.0
        max_trade_amount = self.config.max_trade_amount
        leverage = self.config.leverage

        # 3. Iterate candles
        for i in range(2, len(candles)):
            window = candles[: i + 1]
            current = candles[i]

            # If we have an open trade, check SL and TP first
            if open_trade is not None:
                should_close = False
                exit_price = current.close
                exit_reason = "signal"

                # Check Stop Loss
                if open_trade.side == "BUY":
                    sl_price = open_trade.entry_price * (1 - self.config.stop_loss_percent / 100.0) if self.config.stop_loss_percent else None
                    tp_price = open_trade.entry_price * (1 + self.config.take_profit_percent / 100.0) if self.config.take_profit_percent else None

                    if sl_price and current.low <= sl_price:
                        should_close = True
                        exit_price = sl_price
                        exit_reason = "stop_loss"
                    elif tp_price and current.high >= tp_price:
                        should_close = True
                        exit_price = tp_price
                        exit_reason = "take_profit"
                else:  # SELL (short)
                    sl_price = open_trade.entry_price * (1 + self.config.stop_loss_percent / 100.0) if self.config.stop_loss_percent else None
                    tp_price = open_trade.entry_price * (1 - self.config.take_profit_percent / 100.0) if self.config.take_profit_percent else None

                    if sl_price and current.high >= sl_price:
                        should_close = True
                        exit_price = sl_price
                        exit_reason = "stop_loss"
                    elif tp_price and current.low <= tp_price:
                        should_close = True
                        exit_price = tp_price
                        exit_reason = "take_profit"

                # Check exit signal from strategy
                if not should_close:
                    signals = await strategy.analyze(window)
                    for sig in signals:
                        if sig.type == "exit" and sig.side == open_trade.side:
                            should_close = True
                            exit_price = sig.price
                            exit_reason = "signal"
                            break

                if should_close:
                    # Close the trade
                    if open_trade.side == "BUY":
                        pnl = (exit_price - open_trade.entry_price) * open_trade.quantity * leverage
                    else:  # SELL
                        pnl = (open_trade.entry_price - exit_price) * open_trade.quantity * leverage

                    balance += pnl
                    open_trade.exit_price = exit_price
                    open_trade.exit_time = current.timestamp
                    open_trade.pnl = pnl
                    open_trade.exit_reason = exit_reason
                    trades.append(open_trade)
                    open_trade = None

                    # Send notification (fire-and-forget)
                    await self._notify_trade_closed(trades[-1], exit_reason)

                    # Track drawdown
                    if balance > peak_balance:
                        peak_balance = balance
                    dd = (peak_balance - balance) / peak_balance * 100 if peak_balance > 0 else 0
                    if dd > max_drawdown:
                        max_drawdown = dd

            # If no open position, check entry signals
            if open_trade is None:
                signals = await strategy.analyze(window)
                for sig in signals:
                    if sig.type == "entry":
                        # Calculate position size
                        position_value = min(max_trade_amount, balance * leverage)
                        quantity = position_value / sig.price if sig.price > 0 else 0

                        open_trade = Trade(
                            side=sig.side,
                            entry_price=sig.price,
                            entry_time=current.timestamp,
                            quantity=quantity,
                        )
                        break  # One entry signal at a time

        # 4. Close any remaining open position at last price
        if open_trade is not None:
            last_price = candles[-1].close
            if open_trade.side == "BUY":
                pnl = (last_price - open_trade.entry_price) * open_trade.quantity * leverage
            else:
                pnl = (open_trade.entry_price - last_price) * open_trade.quantity * leverage

            balance += pnl
            open_trade.exit_price = last_price
            open_trade.exit_time = candles[-1].timestamp
            open_trade.pnl = pnl
            open_trade.exit_reason = "force_close"
            trades.append(open_trade)

            # Send notification (fire-and-forget)
            await self._notify_trade_closed(open_trade, "force_close")

            if balance > peak_balance:
                peak_balance = balance
            dd = (peak_balance - balance) / peak_balance * 100 if peak_balance > 0 else 0
            if dd > max_drawdown:
                max_drawdown = dd

        # 5. Compute metrics
        metrics = self._compute_metrics(trades, balance, max_drawdown)
        return trades, metrics

    def _compute_metrics(
        self,
        trades: List[Trade],
        final_balance: float,
        max_drawdown: float,
    ) -> Metrics:
        """Compute aggregated performance metrics from a list of trades."""
        total_trades = len(trades)
        win_trades = sum(1 for t in trades if t.pnl > 0)
        loss_trades = sum(1 for t in trades if t.pnl <= 0)
        win_rate = win_trades / total_trades if total_trades > 0 else 0.0
        profit_loss = sum(t.pnl for t in trades)

        # Sharpe ratio (simplified: uses trade returns)
        sharpe = 0.0
        if total_trades > 1:
            returns = [t.pnl / (self.config.virtual_balance or 1) for t in trades]
            mean_return = sum(returns) / len(returns)
            variance = sum((r - mean_return) ** 2 for r in returns) / (len(returns) - 1)
            if variance > 0:
                sharpe = (mean_return / math.sqrt(variance)) * math.sqrt(252)  # Annualized

        return Metrics(
            total_trades=total_trades,
            win_trades=win_trades,
            loss_trades=loss_trades,
            win_rate=win_rate,
            profit_loss=profit_loss,
            final_balance=final_balance,
            max_drawdown=max_drawdown,
            sharpe=sharpe,
        )

    async def stop(self) -> None:
        """Gracefully stop the running engine."""
        pass
