"""Trading engine — orchestrates the strategy execution loop.

Runs a strategy against historical or live data, manages positions,
and collects performance metrics.
"""

from __future__ import annotations

import math
from datetime import datetime
from typing import List, Optional, Tuple

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

    async def run_history(self, candles: List[Candle]) -> Tuple[List[Trade], Metrics]:
        """Run strategy against historical data and return trades + metrics."""
        return await self._execute(candles)

    async def run_virtual(self, candles: List[Candle]) -> Tuple[List[Trade], Metrics]:
        """Run strategy on virtual balance (same logic as history)."""
        return await self._execute(candles)

    async def run_real(self, candles: List[Candle]) -> Tuple[List[Trade], Metrics]:
        """Run strategy with real data (same logic for now — no exchange orders)."""
        return await self._execute(candles)

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
                    trades.append(open_trade)
                    open_trade = None

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
            trades.append(open_trade)

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
