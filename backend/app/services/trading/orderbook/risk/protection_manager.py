"""Система защит для Order Book Engine.

freqtrade: plugins/protectionmanager.py + plugins/protections/ (4 защиты)
"""
from __future__ import annotations

from collections import deque
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Optional

from app.services.trading.orderbook.models import OrderBookConfig, Trade


@dataclass
class ProtectionReturn:
    """Результат срабатывания защиты."""
    stop: bool
    until: Optional[datetime] = None
    reason: str = ""
    pair: Optional[str] = None


class IProtection:
    """Интерфейс защиты. freqtrade: IProtection"""

    has_global_stop: bool = False
    has_local_stop: bool = False

    def on_trade(self, trade: Trade) -> None:
        pass

    def global_stop(self) -> Optional[ProtectionReturn]:
        return None

    def stop_per_pair(self, pair: str) -> Optional[ProtectionReturn]:
        return None


class CooldownProtection(IProtection):
    """Защита 1: пауза после выхода из сделки.

    freqtrade: CooldownProtection
    """
    has_local_stop = True

    def __init__(self, config: OrderBookConfig):
        self._cooldown = config.cooldown_seconds
        self._last_exit: dict[str, datetime] = {}

    def on_trade(self, trade: Trade) -> None:
        if trade.exit_time:
            self._last_exit[trade.pair] = trade.exit_time

    def stop_per_pair(self, pair: str) -> Optional[ProtectionReturn]:
        now = datetime.now(timezone.utc)
        last = self._last_exit.get(pair)
        if last and (now - last).total_seconds() < self._cooldown:
            return ProtectionReturn(
                stop=True,
                until=last + timedelta(seconds=self._cooldown),
                reason=f"Cooldown ({self._cooldown}s)",
                pair=pair,
            )
        return None


class LowProfitProtection(IProtection):
    """Защита 2: блокировка пары если средний профит низкий.

    freqtrade: LowProfitProtection
    """
    has_local_stop = True

    def __init__(self, trade_limit: int = 10,
                 min_avg_profit_pct: float = 0.5,
                 stop_duration_seconds: int = 600):
        self._trade_limit = trade_limit
        self._min_profit = min_avg_profit_pct
        self._stop_duration = stop_duration_seconds
        self._history: dict[str, deque] = {}

    def on_trade(self, trade: Trade) -> None:
        if trade.pair not in self._history:
            self._history[trade.pair] = deque(maxlen=self._trade_limit)
        self._history[trade.pair].append(trade.pnl_pct)

    def stop_per_pair(self, pair: str) -> Optional[ProtectionReturn]:
        h = self._history.get(pair)
        if not h or len(h) < self._trade_limit:
            return None
        avg = sum(h) / len(h)
        if avg < self._min_profit:
            return ProtectionReturn(
                stop=True,
                until=datetime.now(timezone.utc)
                     + timedelta(seconds=self._stop_duration),
                reason=f"LowProfit: avg={avg:.2f}% < {self._min_profit:.1f}%",
                pair=pair,
            )
        return None


class MaxDrawdownProtection(IProtection):
    """Защита 3: глобальный стоп при просадке > порога.

    freqtrade: MaxDrawdownProtection
    """
    has_global_stop = True

    def __init__(self, max_drawdown_pct: float = 5.0,
                 lookback_trades: int = 30,
                 stop_duration_seconds: int = 3600):
        self._max_dd = max_drawdown_pct
        self._lookback = lookback_trades
        self._stop_duration = stop_duration_seconds
        self._history: deque[Trade] = deque(maxlen=lookback_trades)

    def on_trade(self, trade: Trade) -> None:
        self._history.append(trade)

    def global_stop(self) -> Optional[ProtectionReturn]:
        if len(self._history) < self._lookback:
            return None
        losses = sum(t.pnl for t in self._history if t.pnl < 0)
        wins = sum(t.pnl for t in self._history if t.pnl > 0)
        gross = wins if wins != 0 else 1
        dd = abs(losses) / gross * 100
        if dd > self._max_dd:
            return ProtectionReturn(
                stop=True,
                until=datetime.now(timezone.utc)
                     + timedelta(seconds=self._stop_duration),
                reason=f"MaxDrawdown: {dd:.1f}% > {self._max_dd:.1f}%",
            )
        return None


class StoplossGuardProtection(IProtection):
    """Защита 4: блокировка если >20% сделок закончились SL.

    freqtrade: StoplossGuard
    """
    has_local_stop = True

    def __init__(self, trade_limit: int = 10,
                 max_stoploss_ratio: float = 0.20,
                 stop_duration_seconds: int = 300):
        self._trade_limit = trade_limit
        self._max_sl = max_stoploss_ratio
        self._stop_duration = stop_duration_seconds
        self._history: dict[str, deque] = {}

    def on_trade(self, trade: Trade) -> None:
        if trade.pair not in self._history:
            self._history[trade.pair] = deque(maxlen=self._trade_limit)
        self._history[trade.pair].append(trade)

    def stop_per_pair(self, pair: str) -> Optional[ProtectionReturn]:
        h = self._history.get(pair)
        if not h or len(h) < self._trade_limit:
            return None
        sl_count = sum(1 for t in h if t.exit_type == "STOP_LOSS")
        sl_ratio = sl_count / len(h)
        if sl_ratio > self._max_sl:
            return ProtectionReturn(
                stop=True,
                until=datetime.now(timezone.utc)
                     + timedelta(seconds=self._stop_duration),
                reason=f"StoplossGuard: {sl_ratio:.0%} SL > {self._max_sl:.0%}",
                pair=pair,
            )
        return None


class ProtectionManager:
    """Менеджер защит. freqtrade: ProtectionManager"""

    def __init__(self, config: OrderBookConfig):
        self._protections = [
            CooldownProtection(config),
            LowProfitProtection(),
            MaxDrawdownProtection(),
            StoplossGuardProtection(),
        ]

    def on_trade_exit(self, trade: Trade) -> None:
        for p in self._protections:
            p.on_trade(trade)

    def global_stop(self) -> Optional[ProtectionReturn]:
        for p in self._protections:
            if p.has_global_stop:
                r = p.global_stop()
                if r:
                    return r
        return None

    def stop_per_pair(self, pair: str) -> Optional[ProtectionReturn]:
        for p in self._protections:
            if p.has_local_stop:
                r = p.stop_per_pair(pair)
                if r:
                    return r
        return None
