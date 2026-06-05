"""Order Book data models.

Вдохновлено: ccxt OrderBook (snapshot + diff),
freqtrade Trade + ExitType + Order.
"""
from __future__ import annotations

from collections import deque
from dataclasses import dataclass, field
from datetime import datetime, timezone
from enum import Enum
from typing import Optional


@dataclass
class OrderBookSnapshot:
    """Снапшот стакана в один момент времени.

    ccxt: OrderBook.bids / .asks (ArrayCacheByPriceLimit)
    """
    pair: str
    timestamp: datetime
    bids: list[tuple[float, float]]  # [(price, qty), ...] sorted DESC
    asks: list[tuple[float, float]]  # [(price, qty), ...] sorted ASC

    @property
    def mid_price(self) -> float:
        if not self.bids or not self.asks:
            return 0.0
        return (self.bids[0][0] + self.asks[0][0]) / 2

    @property
    def bid_price(self) -> float:
        return self.bids[0][0] if self.bids else 0.0

    @property
    def ask_price(self) -> float:
        return self.asks[0][0] if self.asks else 0.0

    @property
    def spread_pct(self) -> float:
        mid = self.mid_price
        if mid <= 0:
            return 999.0
        return (self.ask_price - self.bid_price) / mid * 100

    @property
    def total_bid_volume(self) -> float:
        return sum(q for _, q in self.bids)

    @property
    def total_ask_volume(self) -> float:
        return sum(q for _, q in self.asks)

    @property
    def imbalance(self) -> float:
        """Дисбаланс 0..1. >0.55 = bid, <0.45 = ask."""
        total = self.total_bid_volume + self.total_ask_volume
        if total <= 0:
            return 0.5
        return self.total_bid_volume / total

    @property
    def bid_volume_top5(self) -> float:
        return sum(q for _, q in self.bids[:5])

    @property
    def ask_volume_top5(self) -> float:
        return sum(q for _, q in self.asks[:5])


@dataclass
class OrderBookSignal:
    """Сигнал от стратегии по стакану.

    freqtrade: enter_long/enter_short колонки + enter_tag
    """
    pair: str
    side: str                     # BUY / SELL
    price: float                  # Цена входа
    strategy_name: str
    confidence: float             # 0.0..1.0
    reason: str                   # debug
    exit_after_seconds: int = 60
    entry_tag: str = ""


class ExitType(str, Enum):
    """Причины выхода из сделки.

    freqtrade: enums/exittype.py
    """
    ROI = "ROI"
    STOP_LOSS = "STOP_LOSS"
    TRAILING_STOP_LOSS = "TRAILING_STOP_LOSS"
    EXIT_SIGNAL = "EXIT_SIGNAL"
    FORCE_EXIT = "FORCE_EXIT"
    EMERGENCY_EXIT = "EMERGENCY_EXIT"
    LIQUIDATION = "LIQUIDATION"
    PARTIAL_EXIT = "PARTIAL_EXIT"


@dataclass
class Trade:
    """Открытая/закрытая сделка.

    freqtrade: Trade model (persistence/trade_model.py)
    """
    pair: str
    side: str
    entry_price: float
    entry_time: datetime
    stake_amount: float
    amount: float
    strategy: str

    exit_type: Optional[str] = None
    exit_price: Optional[float] = None
    exit_time: Optional[datetime] = None
    exit_reason: Optional[str] = None
    pnl: float = 0.0
    pnl_pct: float = 0.0

    stop_loss: Optional[float] = None
    max_rate: Optional[float] = None
    min_rate: Optional[float] = None

    def close(self, exit_price: float, exit_time: datetime,
              exit_type: str, exit_reason: str = ""):
        self.exit_price = exit_price
        self.exit_time = exit_time
        self.exit_type = exit_type
        self.exit_reason = exit_reason
        if self.side == "BUY":
            self.pnl_pct = (exit_price - self.entry_price) / self.entry_price * 100
        else:
            self.pnl_pct = (self.entry_price - exit_price) / self.entry_price * 100
        self.pnl = self.pnl_pct / 100 * self.stake_amount

    def age_seconds(self, now: Optional[datetime] = None) -> float:
        now = now or datetime.now(timezone.utc)
        return (now - self.entry_time).total_seconds()

    def current_profit(self, current_price: float) -> float:
        if self.side == "BUY":
            return (current_price - self.entry_price) / self.entry_price * 100
        else:
            return (self.entry_price - current_price) / self.entry_price * 100


@dataclass
class OrderBookConfig:
    """Конфигурация Order Book Engine / стратегий."""
    pairs: list[str] = field(default_factory=lambda: ["BTCUSDT"])
    strategy_name: str = "imbalance_scalping"
    initial_balance: float = 1000.0
    max_open_trades: int = 1

    # Strategy 1: Imbalance Scalping
    imbalance_threshold: float = 0.65
    surge_pct: float = 20.0
    confirmation_ticks: int = 3
    max_spread_pct: float = 0.05

    # Exit
    exit_after_seconds: int = 60
    max_hold_seconds: int = 120
    stoploss: float = -1.0

    # Trailing stop
    trailing_stop: bool = True
    trailing_stop_positive: float = 0.3
    trailing_stop_positive_offset: float = 0.5

    # Protections
    cooldown_seconds: int = 120
    min_trade_interval: int = 10
    max_runtime_hours: int = 0  # 0 = unlimited


class OrderBookCache:
    """Кольцевой буфер снапшотов.

    ccxt: ArrayCache — кэширует последние N элементов.
    Используется стратегиями для анализа тренда за окно.
    """

    def __init__(self, maxlen: int = 100):
        self._buf: deque[OrderBookSnapshot] = deque(maxlen=maxlen)

    def push(self, snap: OrderBookSnapshot) -> None:
        self._buf.append(snap)

    def latest(self) -> Optional[OrderBookSnapshot]:
        return self._buf[-1] if self._buf else None

    def window(self, n: int) -> list[OrderBookSnapshot]:
        return list(self._buf)[-n:]

    @property
    def is_warm(self) -> bool:
        return len(self._buf) >= 10

    @property
    def count(self) -> int:
        return len(self._buf)
