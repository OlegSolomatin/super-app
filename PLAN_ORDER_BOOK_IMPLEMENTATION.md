# Order Book Trading System — Пошаговый план реализации

> **Для Hermes:** Использовать subagent-driven-development, каждую задачу — отдельный subagent.
>
> **Архитектура:** 4 стратегии по стакану на едином движке OrderBookEngine.
> WebSocket (ccxt-style) -> OrderBookCache -> Strategy.analyze() -> [Gatekeeper -> Risk -> Trade].
> Выход: Exit Pipeline из freqtrade (custom_exit -> max_hold -> trailing -> hard stop).
> Защиты: ProtectionManager из freqtrade (Cooldown, LowProfit, MaxDrawdown, StoplossGuard).
>
> **Стек:** Python 3.12, asyncio, aiohttp (WebSocket), dataclasses
>
> **Путь:** `backend/app/services/trading/orderbook/`

---

## Фаза 0: Модели данных

**Цель:** Создать базовые dataclass'ы для Order Book системы.

**Файлы:**
- `backend/app/services/trading/orderbook/__init__.py`
- `backend/app/services/trading/orderbook/models.py`
- `backend/app/services/trading/orderbook/cache.py`

---

### Задача 0.1: Создать структуру папок

**Файл:** Создаётся директории и `__init__.py`

```bash
mkdir -p ~/workspace/super-app/backend/app/services/trading/orderbook/strategies
mkdir -p ~/workspace/super-app/backend/app/services/trading/orderbook/risk
mkdir -p ~/workspace/super-app/backend/app/services/trading/orderbook/rpc
mkdir -p ~/workspace/super-app/backend/app/services/trading/orderbook/exchange
mkdir -p ~/workspace/super-app/backend/app/services/trading/orderbook/db
touch ~/workspace/super-app/backend/app/services/trading/orderbook/__init__.py
```

---

### Задача 0.2: Создать models.py

**Файл:** `backend/app/services/trading/orderbook/models.py`

```python
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

    imbalance_threshold: float = 0.65
    surge_pct: float = 20.0
    confirmation_ticks: int = 3
    max_spread_pct: float = 0.05

    exit_after_seconds: int = 60
    max_hold_seconds: int = 120
    stoploss: float = -1.0

    trailing_stop: bool = True
    trailing_stop_positive: float = 0.3
    trailing_stop_positive_offset: float = 0.5

    cooldown_seconds: int = 120
    min_trade_interval: int = 10


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
```

**Проверка:**
```bash
cd ~/workspace/super-app/backend
python3 -c "from app.services.trading.orderbook.models import *; print('OK')"
```

---

## Фаза 1: WebSocket Fetcher

**Цель:** Получать снапшоты стакана с Binance через WebSocket.

**Файлы:**
- `backend/app/services/trading/orderbook/exchange/__init__.py`
- `backend/app/services/trading/orderbook/exchange/binance_stream.py`

---

### Задача 1.1: Binance WebSocket клиент

**Файл:** `backend/app/services/trading/orderbook/exchange/binance_stream.py`

```python
"""WebSocket поток стакана Binance.

ccxt Pro: client.py + order_book.py (snapshot+diff sync)

Binance depth stream:
  wss://stream.binance.com:9443/ws/<stream>@depth20@100ms
Combined:
  wss://stream.binance.com:9443/stream?streams=<s1>/<s2>
"""
from __future__ import annotations

import asyncio
import json
import logging
from datetime import datetime, timezone
from typing import Callable, Optional

import aiohttp

from app.services.trading.orderbook.models import OrderBookSnapshot

logger = logging.getLogger(__name__)

BINANCE_WS_BASE = "wss://stream.binance.com:9443"

SYMBOL_TO_STREAM = {
    "BTCUSDT": "btcusdt@depth20@100ms",
    "ETHUSDT": "ethusdt@depth20@100ms",
    "SOLUSDT": "solusdt@depth20@100ms",
    "TONUSDT": "tonusdt@depth20@100ms",
    "BNBUSDT": "bnbusdt@depth20@100ms",
}


class BinanceOrderBookStream:
    """WebSocket клиент для получения стакана с Binance.

    При разрыве -- reconnect с exponential backoff.
    """

    def __init__(self, pairs: list[str],
                 on_snapshot: Callable[[OrderBookSnapshot], None]):
        self._pairs = pairs
        self._callback = on_snapshot
        self._ws = None
        self._running = False
        self._reconnect_delay = 1.0

    async def start(self):
        """Запустить WS и слушать до остановки.

        ccxt Pro: Client.connect() + watch()
        """
        self._running = True
        while self._running:
            try:
                await self._connect_and_listen()
            except Exception as e:
                if not self._running:
                    break
                logger.warning(
                    f"[OBFetcher] Error: {e}. "
                    f"Reconnect in {self._reconnect_delay}s..."
                )
                await asyncio.sleep(self._reconnect_delay)
                self._reconnect_delay = min(self._reconnect_delay * 2, 60.0)

    async def _connect_and_listen(self):
        streams = [
            SYMBOL_TO_STREAM[p.upper()]
            for p in self._pairs
            if p.upper() in SYMBOL_TO_STREAM
        ]
        if not streams:
            logger.error(f"[OBFetcher] No known pairs: {self._pairs}")
            return

        url = f"{BINANCE_WS_BASE}/stream?streams={'/'.join(streams)}"
        logger.info(f"[OBFetcher] Connecting to {url}")

        async with aiohttp.ClientSession() as session:
            async with session.ws_connect(url, heartbeat=30.0) as ws:
                self._ws = ws
                self._reconnect_delay = 1.0
                logger.info(f"[OBFetcher] Connected ({len(streams)} streams)")

                async for msg in ws:
                    if not self._running:
                        break
                    if msg.type == aiohttp.WSMsgType.TEXT:
                        self._on_message(msg.data)
                    elif msg.type in (aiohttp.WSMsgType.CLOSED,
                                      aiohttp.WSMsgType.ERROR):
                        break

    def _on_message(self, raw: str):
        """Парсинг сообщения -> OrderBookSnapshot.

        ccxt: parse_order_book()
        """
        try:
            msg = json.loads(raw)
            data = msg.get("data", msg)
            pair = data.get("s", "")
            bids_raw = data.get("b", [])
            asks_raw = data.get("a", [])
            if not pair or not bids_raw or not asks_raw:
                return
            bids = [(float(p), float(q)) for p, q in bids_raw if float(q) > 0]
            asks = [(float(p), float(q)) for p, q in asks_raw if float(q) > 0]
            snap = OrderBookSnapshot(
                pair=pair,
                timestamp=datetime.now(timezone.utc),
                bids=bids,
                asks=asks,
            )
            self._callback(snap)
        except (json.JSONDecodeError, KeyError, ValueError, TypeError) as e:
            logger.debug(f"[OBFetcher] Parse error: {e}")

    async def stop(self):
        self._running = False
        if self._ws and not self._ws.closed:
            await self._ws.close()
        logger.info("[OBFetcher] Stopped")
```

**Проверка:**
```bash
cd ~/workspace/super-app/backend
python3 -c "from app.services.trading.orderbook.exchange.binance_stream import BinanceOrderBookStream; print('OK')"
```

---

## Фаза 2: Базовый класс стратегии

**Цель:** Интерфейс для всех Order Book стратегий (как IStrategy из freqtrade).

**Файлы:**
- `backend/app/services/trading/orderbook/strategies/__init__.py`
- `backend/app/services/trading/orderbook/strategies/base.py`

---

### Задача 2.1: AbstractOrderBookStrategy

**Файл:** `backend/app/services/trading/orderbook/strategies/base.py`

```python
"""Базовый класс для Order Book стратегий.

freqtrade: IStrategy (interface.py) -- ~40 атрибутов + 20 коллбэков.
Адаптировано под стакан.
"""
from __future__ import annotations

from abc import ABC, abstractmethod
from typing import Optional

from app.services.trading.orderbook.models import (
    OrderBookCache,
    OrderBookConfig,
    OrderBookSignal,
    OrderBookSnapshot,
    Trade,
)


class AbstractOrderBookStrategy(ABC):
    """Базовый класс стратегии торговли по стакану.

    Обязательный метод: analyze().
    Опциональные: confirm_trade_entry(), custom_exit().
    """

    name: str = ""

    def __init__(self, config: OrderBookConfig):
        self.config = config

    @abstractmethod
    def analyze(self, snap: OrderBookSnapshot,
                cache: OrderBookCache) -> Optional[OrderBookSignal]:
        """Оценить текущий тик стакана.

        freqtrade: populate_indicators() + populate_entry_trend()
        Вызывается на каждый снапшот (~100ms).
        """
        ...

    def confirm_trade_entry(self, signal: OrderBookSignal) -> bool:
        """Gatekeeper: подтвердить вход перед исполнением.

        freqtrade: IStrategy.confirm_trade_entry()
        """
        return True

    def custom_exit(self, trade: Trade, snap: OrderBookSnapshot,
                    cache: OrderBookCache) -> Optional[str]:
        """Кастомный сигнал выхода.

        freqtrade: IStrategy.custom_exit()
        """
        return None

    def custom_stoploss(self, trade: Trade,
                        current_price: float) -> float:
        """Динамический стоп-лосс. Не может превысить config.stoploss.

        freqtrade: IStrategy.custom_stoploss()
        """
        return self.config.stoploss

    def custom_stake_amount(self, proposed_stake: float,
                            free_balance: float) -> float:
        return proposed_stake
```

**Проверка:**
```bash
cd ~/workspace/super-app/backend
python3 -c "from app.services.trading.orderbook.strategies.base import AbstractOrderBookStrategy; print('OK')"
```

---

## Фаза 3: Стратегия 1 — Imbalance Scalping

**Цель:** Торговля по дисбалансу стакана с 3-тик подтверждением.

**Файл:**
- `backend/app/services/trading/orderbook/strategies/imbalance_scalping.py`

---

### Задача 3.1: ImbalanceScalpingStrategy

**Файл:** `backend/app/services/trading/orderbook/strategies/imbalance_scalping.py`

```python
"""Strategy 1: Imbalance Scalping.

Ловит момент, когда одна сторона стакана резко доминирует.

Сигнал BUY:
  1. imbalance > threshold (0.65)
  2. bid_volume вырос > surge% за 5 тиков
  3. spread < max_spread (0.05%)
  4. 3 тика подряд imbalance > 0.55
  5. Не iceberg

Выход: нормализация дисбаланса или max hold.
"""
from __future__ import annotations

from typing import Optional

from app.services.trading.orderbook.models import (
    OrderBookCache,
    OrderBookConfig,
    OrderBookSignal,
    OrderBookSnapshot,
    Trade,
)
from app.services.trading.orderbook.strategies.base import (
    AbstractOrderBookStrategy,
)


class ImbalanceScalpingStrategy(AbstractOrderBookStrategy):
    """Стратегия торговли по дисбалансу стакана."""

    name = "imbalance_scalping"

    def __init__(self, config: OrderBookConfig):
        super().__init__(config)

    def analyze(self, snap: OrderBookSnapshot,
                cache: OrderBookCache) -> Optional[OrderBookSignal]:
        c = self.config

        # Защита: спред
        if snap.spread_pct > c.max_spread_pct:
            return None

        # Защита: iceberg
        if self._is_iceberg(snap):
            return None

        window = cache.window(c.confirmation_ticks + 2)
        if len(window) < c.confirmation_ticks:
            return None

        imb = snap.imbalance
        surge_bid = self._volume_surge(window, "bid")
        surge_ask = self._volume_surge(window, "ask")

        # BUY
        if (imb > c.imbalance_threshold
                and surge_bid > c.surge_pct
                and self._confirm_trend(window, 0.55, "bid")):
            return OrderBookSignal(
                pair=snap.pair,
                side="BUY",
                price=snap.ask_price,
                strategy_name=self.name,
                confidence=min(imb, 0.95),
                reason=f"imb={imb:.3f} surge={surge_bid:.1f}%",
                exit_after_seconds=c.exit_after_seconds,
                entry_tag="imbalance_buy",
            )

        # SELL
        if ((1 - imb) > c.imbalance_threshold
                and surge_ask > c.surge_pct
                and self._confirm_trend(window, 0.45, "ask")):
            return OrderBookSignal(
                pair=snap.pair,
                side="SELL",
                price=snap.bid_price,
                strategy_name=self.name,
                confidence=min(1 - imb, 0.95),
                reason=f"imb={imb:.3f} surge={surge_ask:.1f}%",
                exit_after_seconds=c.exit_after_seconds,
                entry_tag="imbalance_sell",
            )

        return None

    def custom_exit(self, trade: Trade, snap: OrderBookSnapshot,
                    cache: OrderBookCache) -> Optional[str]:
        """Выход при нормализации дисбаланса.

        freqtrade: IStrategy.custom_exit()
        """
        imb = snap.imbalance
        if trade.side == "BUY" and imb < 0.55:
            return "imbalance_normalized"
        if trade.side == "SELL" and imb > 0.45:
            return "imbalance_normalized"
        return None

    def _is_iceberg(self, snap: OrderBookSnapshot) -> bool:
        if len(snap.bids) >= 2:
            if (snap.bids[0][1] > snap.bids[1][1] * 5
                    and snap.bids[1][1] > 0):
                return True
        if len(snap.asks) >= 2:
            if (snap.asks[0][1] > snap.asks[1][1] * 5
                    and snap.asks[1][1] > 0):
                return True
        return False

    def _volume_surge(self, window: list, side: str) -> float:
        if len(window) < 2:
            return 0.0
        vol_0 = (window[0].total_bid_volume if side == "bid"
                 else window[0].total_ask_volume)
        vol_n = (window[-1].total_bid_volume if side == "bid"
                 else window[-1].total_ask_volume)
        if vol_0 <= 0:
            return 0.0
        return (vol_n - vol_0) / vol_0 * 100

    def _confirm_trend(self, window: list,
                       threshold: float, side: str) -> bool:
        recent = window[-self.config.confirmation_ticks:]
        if side == "bid":
            for snap in recent:
                if snap.imbalance < threshold:
                    return False
        else:
            for snap in recent:
                if snap.imbalance > (1 - threshold):
                    return False
        return True
```

**Проверка:**
```bash
cd ~/workspace/super-app/backend
python3 -c "from app.services.trading.orderbook.strategies.imbalance_scalping import ImbalanceScalpingStrategy; print('OK')"
```

---

## Фаза 4: ProtectionManager + Wallets + PairLock

**Цель:** 4 защиты из freqtrade + управление балансом + блокировка пар.

**Файлы:**
- `backend/app/services/trading/orderbook/risk/__init__.py`
- `backend/app/services/trading/orderbook/risk/protection_manager.py`
- `backend/app/services/trading/orderbook/risk/wallets.py`
- `backend/app/services/trading/orderbook/risk/pairlock.py`

---

### Задача 4.1: ProtectionManager

**Файл:** `backend/app/services/trading/orderbook/risk/protection_manager.py`

```python
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
```

---

### Задача 4.2: Wallets

**Файл:** `backend/app/services/trading/orderbook/risk/wallets.py`

```python
"""Управление балансом и расчёт размера ставки.

freqtrade: wallets.py
"""


class Wallets:
    """Виртуальный баланс.

    Формула ставки: free_balance / max_open_trades
    """

    def __init__(self, initial_balance: float = 1000.0,
                 max_open_trades: int = 1):
        self.initial_balance = initial_balance
        self.max_open_trades = max(max_open_trades, 1)
        self._free = initial_balance
        self._locked: dict[str, float] = {}

    def get_trade_stake_amount(self, pair: str) -> float:
        amount = self._free / self.max_open_trades
        if amount < 10.0:
            return 0.0
        return amount

    def lock_stake(self, pair: str, amount: float) -> None:
        self._free -= amount
        self._locked[pair] = amount

    def unlock_stake(self, pair: str, pnl: float) -> None:
        locked = self._locked.pop(pair, 0.0)
        self._free += locked + pnl

    @property
    def free_balance(self) -> float:
        return self._free

    @property
    def total_balance(self) -> float:
        return self._free + sum(self._locked.values())

    @property
    def locked_in_trades(self) -> dict[str, float]:
        return dict(self._locked)
```

---

### Задача 4.3: PairLock

**Файл:** `backend/app/services/trading/orderbook/risk/pairlock.py`

```python
"""Блокировка пар после сделки.

freqtrade: PairLock model
"""
from __future__ import annotations

from datetime import datetime, timezone
from typing import Optional


class PairLockManager:
    """In-memory блокировка пар."""

    def __init__(self):
        self._locks: dict[str, tuple[datetime, str]] = {}

    def lock(self, pair: str, until: datetime, reason: str = ""):
        self._locks[pair] = (until, reason)

    def is_locked(self, pair: str) -> bool:
        now = datetime.now(timezone.utc)
        if pair not in self._locks:
            return False
        until, _ = self._locks[pair]
        if now >= until:
            del self._locks[pair]
            return False
        return True

    def unlock(self, pair: str):
        self._locks.pop(pair, None)

    @property
    def active_locks(self) -> list[tuple[str, datetime, str]]:
        now = datetime.now(timezone.utc)
        return [(p, u, r) for p, (u, r) in self._locks.items() if u > now]
```

---

## Фаза 5: OrderBookEngine — главный движок

**Цель:** Объединить WebSocket, стратегию, защиты и управление позициями.

**Файл:**
- `backend/app/services/trading/orderbook/engine.py`

---

### Задача 5.1: OrderBookEngine

**Файл:** `backend/app/services/trading/orderbook/engine.py`

```python
"""Order Book Engine -- главный цикл для стаканных стратегий.

freqtrade: FreqtradeBot.process() -- основной цикл.
ccxt: Client.on_message_callback -- тики из WS.

Отличие от свечного engine.py:
- Работает на тиках стакана (100ms), не на свечах
- Только virtual mode
- Свой lifecycle: Fetcher -> Cache -> Strategy -> [Gatekeeper -> Risk -> Trade]
"""
from __future__ import annotations

import asyncio
import logging
from datetime import datetime, timedelta, timezone
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

logger = logging.getLogger(__name__)

STRATEGY_REGISTRY = {
    "imbalance_scalping": ImbalanceScalpingStrategy,
}


def load_strategy(config: OrderBookConfig) -> AbstractOrderBookStrategy:
    """Factory: загрузить стратегию по имени.

    freqtrade: StrategyResolver.load_strategy()
    """
    cls = STRATEGY_REGISTRY.get(config.strategy_name)
    if cls is None:
        raise ValueError(f"Unknown: {config.strategy_name}. "
                         f"Available: {list(STRATEGY_REGISTRY.keys())}")
    return cls(config)


class OrderBookEngine:
    """Главный движок Order Book стратегий.

    Один инстанс = один запуск для одной пары.
    """

    def __init__(self, config: OrderBookConfig):
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

        self.metrics = {
            "signals_generated": 0,
            "trades_opened": 0,
            "trades_closed": 0,
            "total_pnl": 0.0,
            "win_count": 0,
            "loss_count": 0,
            "max_drawdown": 0.0,
            "peak_balance": config.initial_balance,
        }

    async def start(self):
        """Запустить движок.

        1. WS fetcher в фоне
        2. Фоновый цикл управления позициями
        """
        if self._running:
            logger.warning("[OBEngine] Already running")
            return

        self._running = True
        logger.info(f"[OBEngine] Start: {self.config.pairs[0]} -> "
                    f"{self.strategy.name}")

        fetcher = BinanceOrderBookStream(
            pairs=self.config.pairs,
            on_snapshot=self._on_snapshot,
        )
        self._fetch_task = asyncio.create_task(fetcher.start())
        self._manage_task = asyncio.create_task(self._manage_loop())

    async def stop(self):
        """Остановить движок и закрыть позиции."""
        self._running = False
        if self._fetch_task:
            self._fetch_task.cancel()
        if self._manage_task:
            self._manage_task.cancel()

        for pair, trade in list(self._trades.items()):
            now = datetime.now(timezone.utc)
            snap = self.cache.latest()
            trade.close(
                exit_price=snap.mid_price if snap else trade.entry_price,
                exit_time=now,
                exit_type=ExitType.FORCE_EXIT.value,
                exit_reason="engine_stop",
            )
            self._trade_history.append(trade)
        self._trades.clear()
        logger.info(f"[OBEngine] Stopped. "
                    f"Trades: {len(self._trade_history)}, "
                    f"PnL: ${self.metrics['total_pnl']:.2f}")

    async def _on_snapshot(self, snap: OrderBookSnapshot):
        """Callback от WebSocket.

        freqtrade: FreqtradeBot.process() -- одна итерация.
        ccxt: Client.on_message_callback.
        """
        if not self._running:
            return

        self.cache.push(snap)
        if not self.cache.is_warm:
            return

        # Protection: global stop
        if self.protection.global_stop():
            logger.warning("[OBEngine] Global stop triggered")
            await self.stop()
            return

        # Protection: per pair
        if self.protection.stop_per_pair(snap.pair):
            return

        # PairLock
        if self.pairlock.is_locked(snap.pair):
            return

        # Already has a position on this pair?
        if snap.pair in self._trades:
            return

        # Strategy
        async with self._lock:
            signal = self.strategy.analyze(snap, self.cache)

        if signal is None:
            return

        self.metrics["signals_generated"] += 1

        # Gatekeeper
        if not self.strategy.confirm_trade_entry(signal):
            return

        # Risk
        stake = self.wallets.get_trade_stake_amount(signal.pair)
        if stake <= 0:
            return

        now = datetime.now(timezone.utc)
        trade = Trade(
            pair=signal.pair,
            side=signal.side,
            entry_price=signal.price,
            entry_time=now,
            stake_amount=stake,
            amount=stake / signal.price,
            strategy=signal.strategy_name,
        )
        self.wallets.lock_stake(signal.pair, stake)
        self._trades[signal.pair] = trade
        self.metrics["trades_opened"] += 1

        self.pairlock.lock(
            signal.pair,
            until=now + timedelta(seconds=self.config.min_trade_interval),
            reason=f"trade:{signal.entry_tag}",
        )

        logger.info(
            f"[OBEngine] ENTRY {signal.side} {signal.pair} "
            f"@{signal.price:.2f} | "
            f"conf={signal.confidence:.2f} | {signal.reason}"
        )

    async def _manage_loop(self):
        """Фоновый цикл: каждую секунду проверяет открытые позиции.

        freqtrade: FreqtradeBot.exit_positions() + handle_trade()

        Exit Pipeline (по приоритету):
          1. custom_exit() -- стратегия
          2. max_hold_seconds -- экстренный
          3. trailing stop -- при профите
          4. hard stoploss
        """
        while self._running:
            await asyncio.sleep(1)
            if not self._trades:
                continue

            snap = self.cache.latest()
            if snap is None:
                continue

            now = datetime.now(timezone.utc)

            for pair, trade in list(self._trades.items()):
                age = trade.age_seconds(now)

                # 1. Custom exit
                ereason = self.strategy.custom_exit(trade, snap, self.cache)
                if ereason:
                    await self._close_trade(
                        trade, snap, ExitType.EXIT_SIGNAL, ereason)
                    continue

                # 2. Max hold
                if age >= self.config.max_hold_seconds:
                    await self._close_trade(
                        trade, snap, ExitType.EMERGENCY_EXIT, "max_hold")
                    continue

                # 3. Trailing stop
                if self.config.trailing_stop:
                    sl = self._check_trailing_stop(trade, snap)
                    if sl:
                        await self._close_trade(
                            trade, snap, ExitType.TRAILING_STOP_LOSS,
                            "trailing")
                        continue

                # 4. Hard stoploss
                sl = self._check_hard_stop(trade, snap)
                if sl:
                    await self._close_trade(
                        trade, snap, ExitType.STOP_LOSS, "stoploss")
                    continue

    async def _close_trade(self, trade: Trade, snap: OrderBookSnapshot,
                           exit_type: ExitType, reason: str):
        """Закрыть сделку.

        freqtrade: FreqtradeBot.execute_trade_exit()
        """
        exit_price = (snap.bid_price if trade.side == "BUY"
                      else snap.ask_price)
        now = datetime.now(timezone.utc)

        trade.close(exit_price=exit_price, exit_time=now,
                    exit_type=exit_type.value, exit_reason=reason)
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
        dd = ((self.metrics["peak_balance"] - total)
              / self.metrics["peak_balance"] * 100)
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
        curr = (snap.bid_price if trade.side == "BUY" else snap.ask_price)
        profit = trade.current_profit(curr)

        if trade.side == "BUY":
            trade.max_rate = max(trade.max_rate or 0, curr)
        else:
            trade.min_rate = min(trade.min_rate or float('inf'), curr)

        if profit < self.config.trailing_stop_positive_offset:
            return None

        dist = self.config.trailing_stop_positive

        if trade.side == "BUY":
            stop = curr * (1 - dist / 100)
            if stop >= curr:
                return None
            trade.stop_loss = max(trade.stop_loss or 0, stop)
            if trade.stop_loss >= curr:
                return trade.stop_loss
        else:
            stop = curr * (1 + dist / 100)
            if stop <= curr:
                return None
            trade.stop_loss = min(trade.stop_loss or float('inf'), stop)
            if trade.stop_loss <= curr:
                return trade.stop_loss
        return None

    def _check_hard_stop(self, trade: Trade,
                         snap: OrderBookSnapshot) -> Optional[float]:
        """freqtrade: hard stoploss."""
        curr = snap.mid_price
        if trade.side == "BUY":
            stop = trade.entry_price * (1 + self.config.stoploss / 100)
            if curr <= stop:
                return stop
        else:
            stop = trade.entry_price * (1 - self.config.stoploss / 100)
            if curr >= stop:
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
        }
```

**Проверка:**
```bash
cd ~/workspace/super-app/backend
python3 -c "
from app.services.trading.orderbook.models import OrderBookConfig
from app.services.trading.orderbook.engine import OrderBookEngine, STRATEGY_REGISTRY
print(f'Engine OK. Strategies: {list(STRATEGY_REGISTRY.keys())}')
"
```

---

## Фаза 6: Запуск движка (скрипт)

**Цель:** Создать скрипт для запуска OrderBookEngine.

**Файл:**
- `backend/app/services/trading/orderbook/run.py`

---

### Задача 6.1: run.py

**Файл:** `backend/app/services/trading/orderbook/run.py`

```python
"""Скрипт запуска Order Book Engine.

Usage:
    python3 -m app.services.trading.orderbook.run
    python3 -m app.services.trading.orderbook.run --pair ETHUSDT \
        --strategy imbalance_scalping --balance 500
"""
from __future__ import annotations

import argparse
import asyncio
import logging
import signal
import sys

from app.services.trading.orderbook.engine import OrderBookEngine
from app.services.trading.orderbook.models import OrderBookConfig

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger("run")


def main():
    parser = argparse.ArgumentParser(description="Order Book Engine")
    parser.add_argument("--pair", default="BTCUSDT")
    parser.add_argument("--strategy", default="imbalance_scalping")
    parser.add_argument("--balance", type=float, default=1000.0)
    parser.add_argument("--max-trades", type=int, default=1)
    args = parser.parse_args()

    config = OrderBookConfig(
        pairs=[args.pair],
        initial_balance=args.balance,
        max_open_trades=args.max_trades,
    )
    config.strategy_name = args.strategy

    engine = OrderBookEngine(config)

    def shutdown():
        logger.info("Shutting down...")
        asyncio.create_task(engine.stop())

    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)

    for sig in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(sig, shutdown)

    try:
        loop.run_until_complete(engine.start())
        loop.run_forever()
    except KeyboardInterrupt:
        pass
    finally:
        loop.run_until_complete(engine.stop())
        loop.close()


if __name__ == "__main__":
    main()
```

**Проверка:**
```bash
cd ~/workspace/super-app/backend
python3 -c "from app.services.trading.orderbook.run import main; print('run.py OK')"
```

---

## Фаза 7: Тестирование

**Цель:** Запустить движок и проверить работу.

---

### Задача 7.1: Запуск с Binance

```bash
cd ~/workspace/super-app/backend
PYTHONPATH=$PWD python3 -m app.services.trading.orderbook.run \
    --pair BTCUSDT --balance 1000
```

**Ожидаемый вывод в логах (первые 30 сек):**
```
[OBFetcher] Connecting to wss://stream.binance.com:9443/stream?streams=btcusdt@depth20@100ms
[OBFetcher] Connected (1 streams)
[OBEngine] Start: BTCUSDT -> imbalance_scalping
... (ждёт 10+ тиков для прогрева кэша) ...
[OBEngine] ENTRY BUY BTCUSDT @67523.50 | conf=0.72 | imb=0.671 surge=23.4%
[OBEngine] EXIT BUY BTCUSDT @67524.80 | pnl=+0.19% | reason=imbalance_normalized
```

### Задача 7.2: Проверка защит

1. **Cooldown:** после EXIT следующая сделка не открывается 120 сек
2. **StoplossGuard:** сэмулировать 3 SL подряд -> пауза на 5 мин
3. **Iceberg guard:** подставить снапшот с bids[0].qty = 10.0, bids[1].qty = 1.0 -> вход заблокирован

---

## Фаза 7: TradingPage — две кнопки выбора визарда

**Цель:** На странице `/trading` разместить две кнопки бок о бок:
- **«Стратегии по свечам»** — открывает существующий `TradingWizardPage` (старый визард)
- **«Стратегии по ордербуку»** — открывает новый `OrderBookWizardPage`

**Файлы:**
- `app/lib/features/trading/presentation/trading_page.dart` — модификация
- `app/lib/features/trading/presentation/orderbook_wizard_page.dart` — создание
- `app/lib/core/router.dart` — модификация (добавить роут `/trading/orderbook-wizard`)

---

### Задача 7.1: Обновить trading_page.dart

**Файл:** `app/lib/features/trading/presentation/trading_page.dart`

**Текущая структура** — `TradingPage` показывает pill-табы (Active / History) и список запусков. Нужно добавить **панель выбора режима** над табами, когда нет активных запусков.

```dart
// В build методе TradingPage, перед табами:
if (_runs.isEmpty && !_isLoading) {
    children.add(_buildModeSelector(context));
}
```

**Новый виджет _buildModeSelector:**

```dart
Widget _buildModeSelector(BuildContext context) {
    final pc = PfColors.of(context);
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Выберите тип стратегии',
            style: PfTypography.titleMd.copyWith(color: pc.foregroundC),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              // Кнопка: Стратегии по свечам
              Expanded(
                child: _ModeCard(
                  icon: PhosphorIconsFill.candle,
                  title: 'Стратегии\nпо свечам',
                  subtitle: 'RSI, MACD, ADX, свечные паттерны\nи 13 других',
                  badge: '17 стратегий',
                  color: const Color(0xFFFCD535),
                  onTap: () => context.go('/trading/wizard'),
                ),
              ),
              const SizedBox(width: 12),
              // Кнопка: Стратегии по ордербуку
              Expanded(
                child: _ModeCard(
                  icon: PhosphorIconsFill.stack,
                  title: 'Стратегии\nпо ордербуку',
                  subtitle: 'Дисбаланс стакана, спред,\nмоментум, iceberg',
                  badge: 'Скоро',
                  color: const Color(0xFF5E6AD2),
                  onTap: () => context.go('/trading/orderbook-wizard'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
}

// ─── Mode Card widget ─────────────────────────────────────────────

class _ModeCard extends StatelessWidget {
    final PhosphorIconData icon;
    final String title;
    final String subtitle;
    final String badge;
    final Color color;
    final VoidCallback onTap;

    const _ModeCard({
        required this.icon,
        required this.title,
        required this.subtitle,
        required this.badge,
        required this.color,
        required this.onTap,
    });

    @override
    Widget build(BuildContext context) {
        final pc = PfColors.of(context);
        final isDark = Theme.of(context).brightness == Brightness.dark;

        return Material(
            color: pc.cardC,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: onTap,
                child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: pc.borderC),
                    ),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                            // Иконка + badge
                            Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                    Container(
                                        width: 44,
                                        height: 44,
                                        decoration: BoxDecoration(
                                            color: color.withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Icon(icon, color: color, size: 22),
                                    ),
                                    Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                            color: color.withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                            badge,
                                            style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w600,
                                                color: color,
                                            ),
                                        ),
                                    ),
                                ],
                            ),
                            const SizedBox(height: 16),
                            // Title
                            Text(
                                title,
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: pc.foregroundC,
                                    height: 1.3,
                                ),
                            ),
                            const SizedBox(height: 6),
                            // Subtitle
                            Text(
                                subtitle,
                                style: TextStyle(
                                    fontSize: 11,
                                    color: pc.mutedForegroundC,
                                    height: 1.4,
                                ),
                            ),
                        ],
                    ),
                ),
            ),
        );
    }
}
```

**Визуальный результат:**
```
┌──────────────────────────────────────────────────┐
│  Выберите тип стратегии                           │
│                                                    │
│  ┌────────────────────┐ ┌────────────────────┐    │
│  │ 🔥 17 стратегий   │ │ 📚 Скоро           │    │
│  │                    │ │                    │    │
│  │ Стратегии          │ │ Стратегии          │    │
│  │ по свечам          │ │ по ордербуку       │    │
│  │                    │ │                    │    │
│  │ RSI, MACD, ADX,    │ │ Дисбаланс стакана, │    │
│  │ свечные паттерны.. │ │ спред, моментум..  │    │
│  └────────────────────┘ └────────────────────┘    │
│                                                    │
│  ┌─ Active ── History ──────────────────────────┐  │
│  │  ...список запусков...                       │  │
│  └──────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────┘
```

---

### Задача 7.2: Добавить роут

**Файл:** `app/lib/core/router.dart`

```dart
import 'package:app/features/trading/presentation/orderbook_wizard_page.dart';

// В секции routes:
GoRoute(
    path: '/trading/orderbook-wizard',
    builder: (context, state) => const OrderBookWizardPage(),
),
```

---

## Фаза 8: OrderBook WizardPage — новый визард настроек

**Цель:** Отдельная страница-визард для настройки и запуска Order Book стратегий.

**Файл:**
- `app/lib/features/trading/presentation/orderbook_wizard_page.dart`

---

### Задача 8.1: OrderBookWizardPage

**Файл:** `app/lib/features/trading/presentation/orderbook_wizard_page.dart`

**Структура визарда (7 шагов с индексами 0-6):**

| Шаг | Название | Что настраивает | Дефолт |
|-----|----------|----------------|--------|
| 0 | **Пара** | Выбор торговой пары | BTCUSDT |
| 1 | **Стратегия** | Выбор OB-стратегии + её параметры | imbalance_scalping |
| 2 | **Баланс** | Стартовый виртуальный баланс | $1000 |
| 3 | **Риски** | Stoploss %, Trailing stop, Max hold | -1%, 0.3%, 120с |
| 4 | **Точность** | Confirmation ticks, Max spread | 3 тика, 0.05% |
| 5 | **Защиты** | Cooldown пауза после сделки | 120 сек |
| 6 | **Запуск** | Сводка + кнопка "Запустить" | — |

---

### Шаг 0: Выбор пары

```
┌─────────────────────────────────┐
│ 🔍 Поиск пары                   │
│ ┌─────────────────────────────┐ │
│ │ BTCUSDT                     │ │
│ │ ETHUSDT                     │ │
│ │ SOLUSDT  ← выбран           │ │
│ │ TONUSDT                     │ │
│ │ BNBUSDT                     │ │
│ └─────────────────────────────┘ │
└─────────────────────────────────┘
```

```dart
// Поле для выбора
String _selectedPair = 'BTCUSDT';
final List<String> _availablePairs = [
    'BTCUSDT', 'ETHUSDT', 'SOLUSDT', 'TONUSDT', 'BNBUSDT',
];

// Виджет:
DropdownButtonFormField<String>(
    value: _selectedPair,
    items: _availablePairs.map((p) => DropdownMenuItem(
        value: p,
        child: Text(p),
    )).toList(),
    onChanged: (v) => setState(() => _selectedPair = v!),
    decoration: InputDecoration(labelText: 'Торговая пара'),
)
```

---

### Шаг 1: Выбор стратегии + её параметры

```
┌─────────────────────────────────────────────┐
│ 📊 Выберите стратегию                        │
│                                              │
│ ◉ Imbalance Scalping   ← выбрана            │
│   Ловит дисбаланс bid/ask с подтверждением   │
│                                              │
│ ○ Spread Capture                             │
│   Торговля по спреду / Market Making Lite    │
│                                              │
│ ○ Order Flow Momentum                        │
│   Агрессивные market orders как сигнал       │
│                                              │
│ Параметры выбранной стратегии:               │
│ ┌─────────────────────────────────────────┐  │
│ │ Imbalance threshold: [0.65] ──●────     │  │
│ │ Volume surge %:        [20]  ──●────    │  │
│ └─────────────────────────────────────────┘  │
└─────────────────────────────────────────────┘
```

```dart
// Модель:
class OrderBookStrategyOption {
    final String name;
    final String label;
    final String description;
    final List<StrategyParam> params;

    const OrderBookStrategyOption({
        required this.name,
        required this.label,
        required this.description,
        this.params = const [],
    });
}

class StrategyParam {
    final String key;
    final String label;
    final double defaultValue;
    final double min;
    final double max;
    final int divisions;

    const StrategyParam({
        required this.key,
        required this.label,
        required this.defaultValue,
        this.min = 0,
        this.max = 100,
        this.divisions = 100,
    });
}

// Доступные стратегии:
final List<OrderBookStrategyOption> _obStrategies = [
    OrderBookStrategyOption(
        name: 'imbalance_scalping',
        label: 'Imbalance Scalping',
        description: 'Ловит дисбаланс bid/ask с 3-тик подтверждением',
        params: [
            StrategyParam(
                key: 'imbalance_threshold',
                label: 'Порог дисбаланса',
                defaultValue: 0.65, min: 0.55, max: 0.85, divisions: 30,
            ),
            StrategyParam(
                key: 'surge_pct',
                label: 'Всплеск объёма %',
                defaultValue: 20, min: 5, max: 50, divisions: 45,
            ),
        ],
    ),
    OrderBookStrategyOption(
        name: 'spread_capture',
        label: 'Spread Capture',
        description: 'Торговля по спреду / Market Making Lite (скоро)',
        params: [],
        enabled: false,
    ),
    OrderBookStrategyOption(
        name: 'order_flow_momentum',
        label: 'Order Flow Momentum',
        description: 'Агрессивные market orders как сигнал (скоро)',
        params: [],
        enabled: false,
    ),
];
```

**Для этого шага — карусель карточек стратегий:**

```dart
Widget _buildStrategyCard(OrderBookStrategyOption s) {
    final selected = _selectedStrategy?.name == s.name;
    return GestureDetector(
        onTap: s.enabled ? () => _selectStrategy(s) : null,
        child: AnimatedContainer(
            duration: Duration(milliseconds: 200),
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: selected ? s.color.withOpacity(0.08) : pc.cardC,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: selected ? s.color : pc.borderC,
                    width: selected ? 1.5 : 1,
                ),
            ),
            child: Row(
                children: [
                    // Radio icon
                    Icon(
                        selected
                            ? PhosphorIconsFill.radioButtonFilled
                            : (s.enabled
                                ? PhosphorIconsFill.radioButton
                                : PhosphorIconsFill.lock),
                        color: selected ? s.color : pc.mutedForegroundC,
                        size: 20,
                    ),
                    SizedBox(width: 12),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                                Text(s.label,
                                    style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: s.enabled
                                            ? pc.foregroundC
                                            : pc.mutedForegroundC,
                                    )),
                                SizedBox(height: 4),
                                Text(s.description,
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: pc.mutedForegroundC,
                                    )),
                            ],
                        ),
                    ),
                ],
            ),
        ),
    );
}
```

---

### Шаг 2: Баланс

```
┌─────────────────────────────────┐
│ 💰 Стартовый баланс             │
│                                 │
│     ┌─────────────────────┐     │
│     │ $ 1000              │     │
│     └─────────────────────┘     │
│                                 │
│  ───●───────────────────────    │
│  $100                    $10000 │
│                                 │
│ Макс. открытых сделок: [1]      │
└─────────────────────────────────┘
```

```dart
// Поля:
double _balance = 1000;
int _maxOpenTrades = 1;

// Виджет:
Column(
    children: [
        TextFormField(
            controller: _balanceController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
                labelText: 'Стартовый баланс ($)',
                prefixText: '$ ',
            ),
        ),
        const SizedBox(height: 16),
        Row(
            children: [
                Text('Макс. открытых сделок:'),
                const SizedBox(width: 12),
                DropdownButton<int>(
                    value: _maxOpenTrades,
                    items: [1,2,3,5].map((v) => DropdownMenuItem(
                        value: v, child: Text('$v'),
                    )).toList(),
                    onChanged: (v) => setState(() => _maxOpenTrades = v!),
                ),
            ],
        ),
    ],
)
```

---

### Шаг 3: Риски

```
┌─────────────────────────────────────────────┐
│ 🛡️ Риски и управление позицией              │
│                                              │
│ Stop Loss:              [-1.0%] ──●────     │
│   Жёсткий предел убытка                      │
│                                              │
│ Trailing Stop:          [0.30%] ──●────     │
│   Подтягивает стоп при профите               │
│                                              │
│ Активация Trailing:     [0.50%] ──●────     │
│   При каком профите включить                 │
│                                              │
│ Max Hold:               [120с]  ──●────     │
│   Максимальное время удержания               │
└─────────────────────────────────────────────┘
```

```dart
double _stoploss = -1.0;           // -1%
double _trailingStop = 0.3;        // 0.3%
double _trailingOffset = 0.5;      // 0.5%
int _maxHoldSeconds = 120;         // 120 сек

// Виджет — Slider + числовое поле для каждого параметра:
Widget _riskSlider(String label, String unit, double value,
                   double min, double max, int divisions,
                   ValueChanged<double> onChanged) {
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
            Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                    Text(label, style: TextStyle(fontSize: 13)),
                    Text('${value.toStringAsFixed(2)}$unit',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13)),
                ],
            ),
            Slider(
                value: value,
                min: min, max: max,
                divisions: divisions,
                onChanged: onChanged,
            ),
        ],
    );
}
```

---

### Шаг 4: Точность

```
┌─────────────────────────────────────────────┐
│ 🎯 Точность и фильтры                       │
│                                              │
│ Confirmation Ticks:     [3]  ──●──────      │
│   Сколько тиков ждать подтверждения тренда   │
│                                              │
│ Max Spread:             [0.05%] ──●────     │
│   Не торговать при слишком широком спреде    │
└─────────────────────────────────────────────┘
```

```dart
int _confirmationTicks = 3;
double _maxSpread = 0.05;  // 0.05%
```

---

### Шаг 5: Защиты

```
┌─────────────────────────────────────────────┐
│ 🔒 Защиты после сделки                      │
│                                              │
│ Cooldown:              [120с]  ──●─────     │
│   Пауза после выхода из сделки               │
│                                              │
│ □ Включить LowProfit защиту                  │
│   (стоп пары при низком профите)             │
│                                              │
│ □ Включить MaxDrawdown защиту                │
│   (глобальный стоп при просадке)             │
└─────────────────────────────────────────────┘
```

---

### Шаг 6: Запуск (сводка + кнопка)

```
┌─────────────────────────────────────────────┐
│ ✅ Сводка конфигурации                       │
│                                              │
│ ┌─ Параметры запуска ──────────────────────┐ │
│ │  Пара:        SOLUSDT                    │ │
│ │  Стратегия:   Imbalance Scalping         │ │
│ │  Баланс:      $1,000.00                  │ │
│ │  Стоп-лосс:   -1.00%                     │ │
│ │  Max Hold:    120 сек                    │ │
│ │  Cooldown:    120 сек                    │ │
│ │  Точность:    3 тика / спред 0.05%       │ │
│ └──────────────────────────────────────────┘ │
│                                              │
│  ⚠️ Работает ТОЛЬКО в virtual режиме         │
│  (реальные данные Binance + виртуальный баланс)│
│                                              │
│  ┌────────────────────────────────────┐      │
│  │  🚀 Запустить Order Book Engine    │      │
│  └────────────────────────────────────┘      │
└─────────────────────────────────────────────┘
```

```dart
Widget _buildSummary() {
    // Сбор всех параметров в OrderBookConfig
    final config = OrderBookConfig(
        pairs: [_selectedPair],
        strategy_name: _selectedStrategy!.name,
        initial_balance: _balance,
        max_open_trades: _maxOpenTrades,
        imbalance_threshold: _params['imbalance_threshold'] ?? 0.65,
        surge_pct: _params['surge_pct'] ?? 20.0,
        confirmation_ticks: _confirmationTicks,
        max_spread_pct: _maxSpread,
        exit_after_seconds: _exitAfterSeconds,
        max_hold_seconds: _maxHoldSeconds,
        stoploss: _stoploss,
        trailing_stop: true,
        trailing_stop_positive: _trailingStop,
        trailing_stop_positive_offset: _trailingOffset,
        cooldown_seconds: _cooldownSeconds,
    );

    return Column(
        children: [
            _SummaryCard(config),  // сводка
            SizedBox(height: 16),
            // Предупреждение
            Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: PfColors.warning.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: PfColors.warning.withOpacity(0.3)),
                ),
                child: Row(
                    children: [
                        Icon(PhosphorIconsFill.warning,
                            color: PfColors.warning, size: 18),
                        SizedBox(width: 10),
                        Expanded(
                            child: Text(
                                'Работает только в virtual режиме — '
                                'реальные данные Binance + виртуальный баланс',
                                style: TextStyle(fontSize: 12),
                            ),
                        ),
                    ],
                ),
            ),
            SizedBox(height: 24),
            // Кнопка запуска
            PfButton(
                variant: 'primary',
                size: 'lg',
                label: '🚀 Запустить Order Book Engine',
                onPressed: _isLoading ? null : _startEngine,
                expanded: true,
            ),
        ],
    );
}
```

---

### Задача 8.2: API эндпоинт для запуска OB Engine

**Файл:** `backend/app/api/v1/trading.py`

```python
from app.services.trading.orderbook.models import OrderBookConfig

@router.post("/orderbook/start")
async def start_orderbook(config: OrderBookConfig):
    """Запустить Order Book Engine с конфигом.

    🔗 OrderBookEngine.start()
    """
    engine = OrderBookEngine(config)
    run_id = str(uuid.uuid4())
    
    # Сохраняем ссылку на движок в глобальном реестре
    _ob_engines[run_id] = engine
    
    asyncio.create_task(engine.start())
    
    return {"run_id": run_id, "status": "running", "pair": config.pairs[0]}


@router.get("/orderbook/status/{run_id}")
async def orderbook_status(run_id: str):
    """Статус запущенного OB Engine.

    🔗 OrderBookEngine.status
    """
    engine = _ob_engines.get(run_id)
    if engine is None:
        raise HTTPException(status_code=404, detail="Run not found")
    return engine.status


@router.post("/orderbook/stop/{run_id}")
async def stop_orderbook(run_id: str):
    """Остановить OB Engine."""
    engine = _ob_engines.pop(run_id, None)
    if engine is None:
        raise HTTPException(status_code=404, detail="Run not found")
    await engine.stop()
    return {"status": "stopped", "run_id": run_id}
```

**Глобальный реестр движков:**

```python
# В конце файла trading.py или в отдельном модуле
_ob_engines: dict[str, OrderBookEngine] = {}
```

---

## 🗺 Сводка (полная)

| Фаза | Задач | Файлов | ⏱ | Описание |
|------|-------|--------|---|----------|
| **0** Модели данных | 2 | 3 | 1ч | Snapshot, Signal, Trade, Cache, Config |
| **1** WebSocket Fetcher | 1 | 2 | 2ч | BinanceOrderBookStream + reconnect |
| **2** AbstractStrategy | 1 | 2 | 1ч | AbstractOrderBookStrategy (IStrategy) |
| **3** Imbalance Scalping | 1 | 1 | 2ч | Основная OB-стратегия |
| **4** Protection + Wallets | 3 | 4 | 2ч | 4 защиты, баланс, блокировка пар |
| **5** OrderBookEngine | 1 | 1 | 3ч | Главный цикл + exit pipeline |
| **6** run.py (запуск) | 1 | 1 | 1ч | CLI скрипт |
| **7** TradingPage UI | 2 | 3 | 2ч | Две кнопки: свечи / ордербук |
| **8** OB Wizard | 2 | 1 | 3ч | 7-шаговый визард + API |
| **9** Тестирование | 2 | — | 1ч | live Binance + защиты |

**MVP (Фазы 0-6):** ~12 часов — backend без UI  
**С UI (Фазы 0-8):** ~17 часов  
**Полный проект:** ~20 часов

---

## 📋 Чеклист перед запуском

- [ ] Все backend файлы импортируются без ошибок
- [ ] WS подключается к Binance и получает снапшоты
- [ ] ImbalanceScalpingStrategy генерирует сигналы
- [ ] ProtectionManager блокирует при падении
- [ ] PairLock не даёт войти повторно
- [ ] Wallets корректно рассчитывает ставку
- [ ] Exit Pipeline закрывает позиции
- [ ] Engine.status() возвращает метрики
- [ ] run.py запускается с аргументами
- [ ] TradingPage показывает две кнопки
- [ ] OB Wizard собирает все параметры
- [ ] API /orderbook/start создаёт и запускает Engine
- [ ] API /orderbook/status возвращает live-метрики
- [ ] API /orderbook/stop останавливает Engine
