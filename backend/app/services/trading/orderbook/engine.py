"""Order Book Engine — главный цикл для стаканных стратегий.

freqtrade: FreqtradeBot.process() — основной цикл.
ccxt: Client.on_message_callback — тики из WS.

Отличие от свечного engine.py:
- Работает на тиках стакана (100ms), не на свечах
- Только virtual mode
- Свой lifecycle: Fetcher -> Cache -> Strategy -> [Gatekeeper -> Risk -> Trade]
"""
from __future__ import annotations

import asyncio
import logging
import os
from collections import deque
from datetime import datetime, timedelta, timezone
from logging.handlers import RotatingFileHandler
from typing import Optional

from app.services.trading.orderbook.exchange.binance_stream import (
    BinanceOrderBookStream,
)
from app.services.trading.orderbook.models import (
    ExitType,
    OrderBookCache,
    OrderBookConfig,
    OrderBookSnapshot,
    Trade,
)
from app.services.trading.orderbook.risk.pairlock import PairLockManager
from app.services.trading.orderbook.risk.protection_manager import (
    ProtectionManager,
)
from app.services.trading.orderbook.risk.wallets import Wallets
from app.services.trading.orderbook.strategies.base import (
    AbstractOrderBookStrategy,
)
from app.services.trading.orderbook.strategies.imbalance_scalping import (
    ImbalanceScalpingStrategy,
)
from app.services.trading.orderbook.strategies.spread_capture import (
    SpreadCaptureStrategy,
)
from app.services.trading.orderbook.strategies.order_flow_momentum import (
    OrderFlowMomentumStrategy,
)
from app.services.trading.orderbook.strategies.ers_scalping import (
    ErsScalpingStrategy,
)

logger = logging.getLogger(__name__)

# File logging for OB signals (5 MB per file, max 3 backups)
_LOG_DIR = os.path.join(os.path.dirname(__file__), "..", "..", "..", "..", "logs")
os.makedirs(_LOG_DIR, exist_ok=True)
_log_file = os.path.join(_LOG_DIR, "ob_signals.log")
_file_handler = RotatingFileHandler(_log_file, maxBytes=5 * 1024 * 1024, backupCount=3)
_file_handler.setLevel(logging.DEBUG)
_file_handler.setFormatter(logging.Formatter(
    "%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
))
# Only add if not already configured
if not logger.handlers:
    logger.addHandler(_file_handler)
    logger.setLevel(logging.DEBUG)

STRATEGY_REGISTRY = {
    "imbalance_scalping": ImbalanceScalpingStrategy,
    "spread_capture": SpreadCaptureStrategy,
    "order_flow_momentum": OrderFlowMomentumStrategy,
    "ers_scalping": ErsScalpingStrategy,
}

MANAGE_LOOP_INTERVAL = 0.5  # проверка позиций каждые 500ms


def load_strategy(config: OrderBookConfig) -> AbstractOrderBookStrategy:
    """Factory: загрузить стратегию по имени.

    freqtrade: StrategyResolver.load_strategy()
    """
    cls = STRATEGY_REGISTRY.get(config.strategy_name)
    if cls is None:
        raise ValueError(
            f"Unknown: {config.strategy_name}. "
            f"Available: {list(STRATEGY_REGISTRY.keys())}"
        )
    return cls(config)


class OrderBookEngine:
    """Главный движок Order Book стратегий.

    Один инстанс = один запуск для одной пары.
    """

    def __init__(self, config: OrderBookConfig,
                 fetcher: Optional[BinanceOrderBookStream] = None):
        self.config = config
        self.strategy = load_strategy(config)
        self.cache = OrderBookCache()
        self.wallets = Wallets(
            initial_balance=config.initial_balance,
            max_open_trades=config.max_open_trades,
        )
        self.protection = ProtectionManager(config)
        self.pairlock = PairLockManager()

        self._trades: dict[str, Trade] = {}
        self._trade_history: list[Trade] = []
        self._fetch_task: Optional[asyncio.Task] = None
        self._manage_task: Optional[asyncio.Task] = None
        self._lock = asyncio.Lock()
        self._running = False

        # Signal history (кольцевой буфер)
        self._signal_history: deque[dict] = deque(maxlen=100)
        self._signal_timestamps: deque[datetime] = deque()

        # Внешний fetcher или создаём свой
        self._fetcher: Optional[BinanceOrderBookStream] = fetcher

        self.metrics = {
            "signals_generated": 0,
            "trades_opened": 0,
            "trades_closed": 0,
            "total_pnl": 0.0,
            "win_count": 0,
            "loss_count": 0,
            "max_drawdown": 0.0,
            "peak_balance": config.initial_balance,
            # Signal rejection counters
            "signals_rejected": 0,
            "signals_per_minute": 0.0,
            "cache_not_warm": 0,
            "global_stop_filtered": 0,
            "pairlock_filtered": 0,
            "has_position_filtered": 0,
            "rejected_spread": 0,
            "rejected_iceberg": 0,
            "rejected_confirm_ticks": 0,
            "rejected_no_signal": 0,
            "rejected_gatekeeper": 0,
            "rejected_wallet": 0,
        }

    def _record_signal(self, signal_type: str | None, status: str,
                        detail: str = "", price: float = 0.0):
        """Записать событие сигнала в историю.

        signal_type: тип сигнала или None (фильтр без сигнала)
        status: 'accepted' | 'filtered'
        detail: причина отказа / reason сигнала
        """
        self._signal_history.append({
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "signal_type": signal_type or "none",
            "status": status,
            "detail": detail,
            "price": round(price, 4) if price else 0.0,
        })

    async def start(self):
        """Запустить движок.

        1. WS fetcher в фоне
        2. Фоновый цикл управления позициями
        """
        if self._running:
            logger.warning("[OBEngine] Already running")
            return

        self._running = True
        logger.info(
            f"[OBEngine] Start: {self.config.pairs[0]} -> "
            f"{self.strategy.name}"
        )

        if self._fetcher is None:
            self._fetcher = BinanceOrderBookStream(
                pairs=self.config.pairs,
                on_snapshot=self._on_snapshot,
            )
        self._fetch_task = asyncio.create_task(self._fetcher.start())
        self._manage_task = asyncio.create_task(self._manage_loop())

    async def stop(self):
        """Остановить движок и закрыть позиции."""
        if not self._running:
            return
        self._running = False

        # 1. Остановить fetcher (закрыть WS)
        if self._fetcher:
            await self._fetcher.stop()

        # 2. Отменить фоновые задачи
        if self._fetch_task and not self._fetch_task.done():
            self._fetch_task.cancel()
        if self._manage_task and not self._manage_task.done():
            self._manage_task.cancel()

        # 3. Закрыть открытые позиции (под блокировкой)
        async with self._lock:
            for pair, trade in list(self._trades.items()):
                now = datetime.now(timezone.utc)
                snap = self.cache.latest()
                exit_price = snap.mid_price if snap else trade.entry_price
                if snap:
                    if trade.side == "BUY":
                        exit_price = snap.bid_price or snap.mid_price
                    else:
                        exit_price = snap.ask_price or snap.mid_price
                trade.close(
                    exit_price=exit_price,
                    exit_time=now,
                    exit_type=ExitType.FORCE_EXIT.value,
                    exit_reason="engine_stop",
                )
                self._trade_history.append(trade)
            self._trades.clear()

        logger.info(
            f"[OBEngine] Stopped. "
            f"Trades: {len(self._trade_history)}, "
            f"PnL: ${self.metrics['total_pnl']:.2f}"
        )

    async def _on_snapshot(self, snap: OrderBookSnapshot):
        """Callback от WebSocket.

        freqtrade: FreqtradeBot.process() — одна итерация.
        ccxt: Client.on_message_callback.
        """
        if not self._running:
            return

        self.cache.push(snap)

        # signals_per_minute — скользящее окно
        now = datetime.now(timezone.utc)
        self._signal_timestamps.append(now)
        cutoff = now - timedelta(seconds=60)
        while self._signal_timestamps and self._signal_timestamps[0] < cutoff:
            self._signal_timestamps.popleft()
        self.metrics["signals_per_minute"] = len(self._signal_timestamps)

        if not self.cache.is_warm:
            self.metrics["cache_not_warm"] += 1
            logger.debug("[OB] %s | cache_not_warm (%d/%d)",
                         snap.pair, self.cache.count + 1, 10)
            return

        # Protection: global stop
        self.protection.update_balance(
            self.wallets.total_balance,
            self.metrics["peak_balance"],
        )
        if self.protection.global_stop():
            logger.warning("[OBEngine] Global stop triggered")
            self.metrics["global_stop_filtered"] += 1
            self._record_signal(None, "filtered", "global_stop")
            await self.stop()
            return

        # Protection: per-pair stop (LowProfit + StoplossGuard)
        pair_stop = self.protection.stop_per_pair(snap.pair)
        if pair_stop and pair_stop.stop:
            logger.warning(
                "[OBEngine] Per-pair stop for %s: %s",
                snap.pair, pair_stop.reason,
            )
            self.metrics["pairlock_filtered"] += 1
            self._record_signal(None, "filtered", f"stop_per_pair: {pair_stop.reason}")
            if pair_stop.until:
                self.pairlock.lock(
                    snap.pair,
                    until=pair_stop.until,
                    reason=pair_stop.reason,
                )
            return

        # PairLock (единственный источник cooldown)
        if self.pairlock.is_locked(snap.pair):
            self.metrics["pairlock_filtered"] += 1
            logger.debug("[OB] %s | pairlock_active", snap.pair)
            self._record_signal(None, "filtered",
                                f"pairlock: {snap.pair}")
            return

        # Already has a position on this pair?
        if snap.pair in self._trades:
            self.metrics["has_position_filtered"] += 1
            logger.debug("[OB] %s | has_position", snap.pair)
            self._record_signal(None, "filtered",
                                f"has_position: {snap.pair}")
            return

        # Strategy
        async with self._lock:
            signal = self.strategy.analyze(snap, self.cache)

        if signal is None:
            self.metrics["rejected_no_signal"] += 1
            self.metrics["signals_rejected"] += 1
            reject_reason = getattr(self.strategy, "_last_rejection", "unknown")
            # Map strategy rejection reason to specific counter
            if "spread" in reject_reason:
                self.metrics["rejected_spread"] += 1
            elif "iceberg" in reject_reason:
                self.metrics["rejected_iceberg"] += 1
            elif "confirm_ticks" in reject_reason or "window" in reject_reason:
                self.metrics["rejected_confirm_ticks"] += 1
            elif "baseline_window" in reject_reason:
                self.metrics["rejected_confirm_ticks"] += 1
            logger.debug("[OB] %s | rejected: %s", snap.pair, reject_reason)
            self._record_signal(None, "filtered",
                                f"strategy: {reject_reason}",
                                price=snap.mid_price)
            return

        self.metrics["signals_generated"] += 1

        # Gatekeeper
        if not self.strategy.confirm_trade_entry(signal):
            self.metrics["rejected_gatekeeper"] += 1
            self.metrics["signals_rejected"] += 1
            logger.debug("[OB] %s | gatekeeper: %s",
                         signal.pair, signal.reason)
            self._record_signal(signal.entry_tag, "filtered",
                                f"gatekeeper: {signal.reason}",
                                price=signal.price)
            return

        # Risk
        stake = self.wallets.get_trade_stake_amount(signal.pair)
        if stake <= 0:
            self.metrics["rejected_wallet"] += 1
            self.metrics["signals_rejected"] += 1
            logger.debug("[OB] %s | wallet: stake=%.2f <= 0",
                         signal.pair, stake)
            self._record_signal(signal.entry_tag, "filtered",
                                f"wallet: stake={stake}", price=signal.price)
            return

        now = datetime.now(timezone.utc)
        if signal.price <= 0:
            logger.debug("[OB] %s | invalid_price: %.4f",
                         signal.pair, signal.price)
            return
        trade = Trade(
            pair=signal.pair,
            side=signal.side,
            entry_price=signal.price,
            entry_time=now,
            stake_amount=stake,
            amount=stake / signal.price,
            strategy=signal.strategy_name,
            exit_after_seconds=signal.exit_after_seconds,
        )
        self.wallets.lock_stake(signal.pair, stake)
        self._trades[signal.pair] = trade
        self.metrics["trades_opened"] += 1

        self.pairlock.lock(
            signal.pair,
            until=now + timedelta(seconds=self.config.min_trade_interval),
            reason=f"trade:{signal.entry_tag}",
        )

        # Record accepted signal
        self._record_signal(signal.entry_tag, "accepted",
                            signal.reason, price=signal.price)

        logger.info(
            f"[OBEngine] ENTRY {signal.side} {signal.pair} "
            f"@{signal.price:.2f} | "
            f"conf={signal.confidence:.2f} | {signal.reason}"
        )

    async def _manage_loop(self):
        """Фоновый цикл: каждые 500ms проверяет открытые позиции.

        freqtrade: FreqtradeBot.exit_positions() + handle_trade()

        Exit Pipeline (по приоритету):
          1. custom_exit() — стратегия
          2. max_hold_seconds — экстренный
          3. trailing stop — при профите
          4. hard stoploss
        """
        while self._running:
            await asyncio.sleep(MANAGE_LOOP_INTERVAL)
            if not self._trades:
                continue

            snap = self.cache.latest()
            if snap is None:
                continue

            now = datetime.now(timezone.utc)

            async with self._lock:
                for pair, trade in list(self._trades.items()):
                    age = trade.age_seconds(now)

                    # 1. Custom exit
                    ereason = self.strategy.custom_exit(trade, snap, self.cache)
                    if ereason:
                        await self._close_trade(
                            trade, snap, ExitType.EXIT_SIGNAL, ereason
                        )
                        continue

                    # 2. Max hold (use per-trade exit_after_seconds)
                    if age >= trade.exit_after_seconds:
                        await self._close_trade(
                            trade, snap, ExitType.EMERGENCY_EXIT, "max_hold"
                        )
                        continue

                    # 3. Trailing stop
                    if self.config.trailing_stop:
                        sl = self._check_trailing_stop(trade, snap)
                        if sl:
                            await self._close_trade(
                                trade, snap,
                                ExitType.TRAILING_STOP_LOSS, "trailing"
                            )
                            continue

                    # 4. Hard stoploss
                    sl = self._check_hard_stop(trade, snap)
                    if sl:
                        await self._close_trade(
                            trade, snap, ExitType.STOP_LOSS, "stoploss"
                        )
                        continue

    async def _close_trade(self, trade: Trade, snap: OrderBookSnapshot,
                           exit_type: ExitType, reason: str):
        """Закрыть сделку.

        freqtrade: FreqtradeBot.execute_trade_exit()
        """
        # Защита от double-close
        if trade.pair not in self._trades:
            return

        exit_price = (
            snap.bid_price if trade.side == "BUY" else snap.ask_price
        )
        if not exit_price:
            exit_price = snap.mid_price or trade.entry_price
        now = datetime.now(timezone.utc)

        trade.close(
            exit_price=exit_price, exit_time=now,
            exit_type=exit_type.value, exit_reason=reason,
        )
        self.wallets.unlock_stake(trade.pair, trade.pnl)
        self._trade_history.append(trade)
        del self._trades[trade.pair]

        self.metrics["trades_closed"] += 1
        self.metrics["total_pnl"] += trade.pnl
        if trade.pnl > 0:
            self.metrics["win_count"] += 1
        else:
            self.metrics["loss_count"] += 1

        total = self.wallets.total_balance
        if total > self.metrics["peak_balance"]:
            self.metrics["peak_balance"] = total
        dd = (
            (self.metrics["peak_balance"] - total)
            / self.metrics["peak_balance"] * 100
        ) if self.metrics["peak_balance"] > 0 else 0.0
        self.metrics["max_drawdown"] = max(self.metrics["max_drawdown"], dd)

        self.protection.on_trade_exit(trade)
        self.pairlock.lock(
            trade.pair,
            until=now + timedelta(seconds=self.config.cooldown_seconds),
            reason=f"exit:{reason}",
        )

        logger.info(
            f"[OBEngine] EXIT {trade.side} {trade.pair} "
            f"@{exit_price:.2f} | "
            f"pnl={trade.pnl_pct:+.2f}% | reason={reason}"
        )

    def _check_trailing_stop(self, trade: Trade,
                             snap: OrderBookSnapshot) -> Optional[float]:
        """freqtrade: trailing stop."""
        curr = (
            snap.bid_price if trade.side == "BUY" else snap.ask_price
        )
        profit = trade.current_profit(curr)

        if trade.side == "BUY":
            trade.max_rate = max(
                (trade.max_rate if trade.max_rate is not None else 0), curr
            )
        else:
            trade.min_rate = min(
                (trade.min_rate if trade.min_rate is not None else float("inf")), curr
            )

        if profit < self.config.trailing_stop_positive_offset:
            return None

        dist = self.config.trailing_stop_positive

        if trade.side == "BUY":
            stop = curr * (1 - dist / 100)
            if stop >= curr:
                return None
            trade.stop_loss = max(
                (trade.stop_loss if trade.stop_loss is not None else 0), stop
            )
            if trade.stop_loss >= curr:
                return trade.stop_loss
        else:
            stop = curr * (1 + dist / 100)
            if stop <= curr:
                return None
            trade.stop_loss = min(
                (trade.stop_loss if trade.stop_loss is not None else float("inf")), stop
            )
            if trade.stop_loss <= curr:
                return trade.stop_loss
        return None

    def _check_hard_stop(self, trade: Trade,
                         snap: OrderBookSnapshot) -> Optional[float]:
        """freqtrade: hard stoploss.
        
        Используем execution price (bid для BUY, ask для SELL),
        а не mid_price (консистентно с _close_trade).
        """
        curr = (
            snap.bid_price if trade.side == "BUY" else snap.ask_price
        )
        if trade.side == "BUY":
            stop = trade.entry_price * (1 + self.config.stoploss / 100)
            if curr <= stop and stop > 0:
                return stop
        else:
            stop = trade.entry_price * (1 - self.config.stoploss / 100)
            if curr >= stop and stop > 0:
                return stop
        return None

    @property
    def status(self) -> dict:
        return {
            "running": self._running,
            "pair": self.config.pairs[0],
            "strategy": self.strategy.name,
            "balance": round(self.wallets.total_balance, 2),
            "free_balance": round(self.wallets.free_balance, 2),
            "open_trades": {
                p: {
                    "side": t.side,
                    "entry_price": t.entry_price,
                    "age_seconds": int(t.age_seconds()),
                }
                for p, t in self._trades.items()
            },
            "metrics": {
                k: round(v, 2) if isinstance(v, float) else v
                for k, v in self.metrics.items()
            },
            "active_locks": self.pairlock.active_locks,
            "recent_signals": list(self._signal_history)[-20:],
        }
