# Order Book Trading System — Полный план

> **База:** freqtrade (51k⭐) + ccxt (42k⭐) — архитектура, паттерны, защиты
> **Суть:** 4 стратегии по стакану на едином движке с ProtectionManager, Risk Management, RPC
> 
> **Ключевое отличие от существующих свечных стратегий:**
> - Данные: WebSocket Order Book (100ms), не OHLCV свечи
> - Режим: ТОЛЬКО virtual (live), нет history backtest
> - Выход: по таймеру/тренду, не по SL/TP %
> - Скорость: решения за миллисекунды, а не минуты

> Создан: 04.06.2026

---

## 📋 Легенда

| Метка | Значение |
|-------|----------|
| 🔴 High | Критично для работы |
| 🟡 Medium | Важно |
| 🟢 Nice | Опционально |
| ⏱ | Оценка времени |
| 🔗 | Ссылка на паттерн из freqtrade/ccxt |

---

## 🔷 Фаза 0: Архитектура — OrderBookEngine

**⏱ 3-4ч · 🔴 High**

### 0.1 Общая архитектура

```diff
 backend/app/services/trading/
+  orderbook/                     # NEW: Order Book модуль
+    __init__.py
+    engine.py                    # OrderBookEngine (главный цикл)
+    fetcher.py                   # WebSocket → снапшоты (из ccxt Pro)
+    cache.py                     # Кольцевой буфер + OrderBook (ccxt-style)
+    metrics.py                   # Имбаланс, спред, объём, моментум
+    strategies/                  # 4 стратегии по стакану
+      base.py                    # AbstractOrderBookStrategy
+      imbalance_scalping.py      # Strategy 1: дисбаланс
+      spread_capture.py          # Strategy 2: спред/MM
+      iceberg_detection.py       # Strategy 3: iceberg
+      order_flow_momentum.py     # Strategy 4: моментум
+    risk/
+      __init__.py
+      protection_manager.py      # ProtectionManager (из freqtrade)
+      protection_cooldown.py     # Защита: Cooldown
+      protection_low_profit.py   # Защита: LowProfit
+      protection_max_drawdown.py # Защита: MaxDrawdown
+      protection_stoploss_guard.py # Защита: StoplossGuard
+      wallets.py                 # Wallets (управление балансом)
+      pairlock.py                # PairLock (блокировка пар)
+    exchange/
+      __init__.py
+      exchange_base.py           # AbstractExchange (ccxt-style)
+      binance_stream.py          # Binance WS (depth20@100ms)
+    rpc/
+      __init__.py
+      manager.py                 # RPCManager (из freqtrade)
+      telegram.py                # TelegramRPC
+    db/
+      __init__.py
+      trade.py                   # Trade ORM (из freqtrade)
+      order.py                   # Order ORM
+      pairlock.py                # PairLock ORM
+  engine.py                      # ← НЕ трогать (свечной движок)
+  models.py                      # ← НЕ трогать + OrderBookSnapshot
+  strategies/                    # ← НЕ трогать (17 свечных стратегий)
```

### 0.2 OrderBookEngine — главный цикл

```python
class OrderBookEngine:
    """Главный движок Order Book стратегий.
    
    Вдохновлён: FreqtradeBot.process() (freqtrade/freqtradebot.py)
    Отличие: работает на тиках стакана, не на свечах.
    """
    
    def __init__(self, config):
        self.config = config
        self.strategy = self._load_strategy(config)
        self.fetcher = BinanceOrderBookStream(config.pairs)
        self.cache = OrderBookCache(maxlen=100)
        self.wallets = Wallets(config)
        self.protection = ProtectionManager(config)
        self.pairlock = PairLockManager()
        self.rpc = RPCManager(config)
        self._trades: dict[str, Trade] = {}  # open trades by pair
        self._trade_history: list[Trade] = []
    
    async def start(self):
        """🔗 freqtrade: FreqtradeBot.start()"""
        await self._init()
        await self.fetcher.start(self._on_snapshot)
    
    async def _init(self):
        self.rpc.send_msg(RPCMessageType.startup, "OrderBookEngine started")
        await self.wallets.initialize()
    
    async def _on_snapshot(self, snap: OrderBookSnapshot):
        """Каждый новый снапшот от WebSocket (~100ms).
        
        🔗 ccxt Pro: Client.on_message_callback
        """
        # 1. Кэшируем
        self.cache.push(snap)
        if not self.cache.is_warm: return
        
        # 2. ProtectionManager — глобальная защита
        if self.protection.global_stop():
            return
        
        # 3. ProtectionManager — защита на пару
        if self.protection.stop_per_pair(snap.pair):
            return
        
        # 4. PairLock — блокировка
        if self.pairlock.is_locked(snap.pair):
            return
        
        # 5. Стратегия — есть ли сигнал
        signal = self.strategy.analyze(snap, self.cache)
        if signal:
            await self._execute(signal)
        
        # 6. Управление открытыми позициями
        await self._manage_positions(snap)
    
    async def _execute(self, signal: OrderBookSignal):
        """🔗 freqtrade: FreqtradeBot.execute_entry()"""
        
        # Gatekeeper: confirm_trade_entry (из IStrategy)
        if not self.strategy.confirm_trade_entry(signal):
            return
        
        # Risk: расчёт размера ставки
        stake = self.wallets.get_trade_stake_amount(signal.pair)
        if stake <= 0:
            return
        
        # Создание сделки
        trade = Trade(
            pair=signal.pair,
            side=signal.side,
            entry_price=signal.price,
            entry_time=datetime.now(timezone.utc),
            stake_amount=stake,
            amount=stake / signal.price,
            strategy=signal.strategy_name,
            exit_type=ExitType.ROI,  # по умолчанию — выход по таймеру
        )
        self._trades[signal.pair] = trade
        
        # RPC: уведомление
        self.rpc.send_msg(RPCMessageType.entry, trade)
        
        # Blocking (защита 4)
        self.pairlock.lock(
            signal.pair,
            until=datetime.now(timezone.utc) + timedelta(seconds=self.config.min_trade_interval),
            reason=f"Trade entered: {signal.strategy_name}"
        )
    
    async def _manage_positions(self, snap: OrderBookSnapshot):
        """🔗 freqtrade: FreqtradeBot.exit_positions() + handle_trade()
        
        Exit Pipeline (по приоритету):
          1. Custom exit (стратегия)
          2. Max hold time
          3. Trailing stop (при профите)
          4. Stop loss
        """
        trade = self._trades.get(snap.pair)
        if not trade: return
        
        now = datetime.now(timezone.utc)
        age = (now - trade.entry_time).total_seconds()
        
        # 1. Custom exit — стратегия сама решает выходить
        exit_signal = self.strategy.custom_exit(trade, snap, self.cache)
        if exit_signal:
            await self._close_trade(trade, snap, ExitType.EXIT_SIGNAL, exit_signal)
            return
        
        # 2. Max hold time (защита 5)
        if age >= self.config.max_hold_seconds:
            await self._close_trade(trade, snap, ExitType.EMERGENCY_EXIT, "max_hold")
            return
        
        # 3. Trailing stop
        if self.config.trailing_stop:
            exit_price = self._check_trailing_stop(trade, snap)
            if exit_price:
                await self._close_trade(trade, snap, ExitType.TRAILING_STOP_LOSS, "trailing")
                return
        
        # 4. Stop loss
        if self.config.stoploss:
            exit_price = self._check_stop_loss(trade, snap)
            if exit_price:
                await self._close_trade(trade, snap, ExitType.STOP_LOSS, "stoploss")
                return
    
    async def _close_trade(self, trade, snap, exit_type, reason=""):
        """Закрыть сделку.
        
        🔗 freqtrade: FreqtradeBot.execute_trade_exit()
        """
        exit_price = snap.mid_price
        
        trade.close(
            exit_price=exit_price,
            exit_time=datetime.now(timezone.utc),
            exit_type=exit_type,
            exit_reason=reason,
        )
        
        # Ручной подсчёт PnL
        if trade.side == "BUY":
            trade.pnl_pct = (exit_price - trade.entry_price) / trade.entry_price * 100
        else:
            trade.pnl_pct = (trade.entry_price - exit_price) / trade.entry_price * 100
        trade.pnl = trade.pnl_pct / 100 * trade.stake_amount
        
        self._trade_history.append(trade)
        del self._trades[trade.pair]
        
        # RPC
        self.rpc.send_msg(RPCMessageType.exit, trade)
        
        # Protection: обновление статистики
        self.protection.on_trade_exit(trade)
        
        # PairLock: блокировка пары после сделки
        lock_duration = self.protection.get_cooldown(trade.pair)
        self.pairlock.lock(
            trade.pair,
            until=datetime.now(timezone.utc) + lock_duration,
            reason=f"exit:{exit_type}"
        )
    
    def _check_trailing_stop(self, trade, snap) -> Optional[float]:
        """🔗 freqtrade: Trailing stop logic (custom_stoploss / trailing_stop)"""
        if not self.config.trailing_stop: return None
        
        current_price = snap.bid_price if trade.side == "BUY" else snap.ask_price
        current_profit = (
            (current_price - trade.entry_price) / trade.entry_price * 100
            if trade.side == "BUY" 
            else (trade.entry_price - current_price) / trade.entry_price * 100
        )
        
        # Обновляем max_rate/min_rate
        if trade.side == "BUY":
            trade.max_rate = max(trade.max_rate or 0, current_price)
        else:
            trade.min_rate = min(trade.min_rate or float('inf'), current_price)
        
        # Активация trailing только после offset
        if current_profit < self.config.trailing_stop_positive_offset:
            return None
        
        stop_distance = self.config.trailing_stop_positive
        
        if trade.side == "BUY":
            stop_price = current_price * (1 - stop_distance / 100)
            # Не поднимаем стоп выше текущей цены
            if stop_price >= current_price: return None
            # Не опускаем стоп
            trade.stop_loss = max(trade.stop_loss or 0, stop_price)
        else:
            stop_price = current_price * (1 + stop_distance / 100)
            if stop_price <= current_price: return None
            trade.stop_loss = min(trade.stop_loss or float('inf'), stop_price)
        
        # Проверка: пробило стоп?
        if trade.side == "BUY" and trade.stop_loss >= current_price:
            return trade.stop_loss
        if trade.side == "SELL" and trade.stop_loss <= current_price:
            return trade.stop_loss
        
        return None
    
    def _check_stop_loss(self, trade, snap) -> Optional[float]:
        """🔗 freqtrade: hard stoploss check"""
        if not self.config.stoploss: return None
        
        current_price = snap.mid_price
        
        if trade.side == "BUY":
            stop_price = trade.entry_price * (1 - self.config.stoploss / 100)
            if current_price <= stop_price:
                return stop_price
        else:
            stop_price = trade.entry_price * (1 + self.config.stoploss / 100)
            if current_price >= stop_price:
                return stop_price
        
        return None
```

### 0.3 Data Models

```python
@dataclass
class OrderBookSnapshot:
    """Снапшот стакана (один тик).
    
    🔗 ccxt: Производное от ccxt.pro OrderBook
    """
    pair: str
    timestamp: datetime
    bids: list[tuple[float, float]]  # [(price, qty), ...] sorted desc
    asks: list[tuple[float, float]]  # [(price, qty), ...] sorted asc
    
    @property
    def mid_price(self) -> float:
        if not self.bids or not self.asks: return 0.0
        return (self.bids[0][0] + self.asks[0][0]) / 2
    
    @property
    def bid_price(self) -> float:
        return self.bids[0][0] if self.bids else 0.0
    
    @property
    def ask_price(self) -> float:
        return self.asks[0][0] if self.asks else 0.0
    
    @property
    def spread_pct(self) -> float:
        """Спред в %."""
        mid = self.mid_price
        if mid <= 0: return 999.0
        return (self.ask_price - self.bid_price) / mid * 100
    
    @property
    def total_bid_volume(self) -> float:
        return sum(q for _, q in self.bids)
    
    @property
    def total_ask_volume(self) -> float:
        return sum(q for _, q in self.asks)
    
    @property
    def imbalance(self) -> float:
        """Дисбаланс 0..1. >0.55 = bid доминирует, <0.45 = ask доминирует."""
        total = self.total_bid_volume + self.total_ask_volume
        if total <= 0: return 0.5
        return self.total_bid_volume / total
    
    @property
    def bid_volume_top5(self) -> float:
        return sum(q for _, q in self.bids[:5])
    
    @property
    def ask_volume_top5(self) -> float:
        return sum(q for _, q in self.asks[:5])


@dataclass
class OrderBookSignal:
    """Сигнал от стратегии по стакану."""
    pair: str
    side: str                    # BUY / SELL
    price: float                 # Цена входа
    strategy_name: str           # Какая стратегия сгенерировала
    confidence: float            # 0.0..1.0
    reason: str                  # Человекочитаемое описание
    exit_after_seconds: int = 60 # Через сколько секунд выйти
    entry_tag: str = ""          # freqtrade-style enter_tag


@dataclass
class Trade:
    """Открытая/закрытая сделка.
    
    🔗 freqtrade: Trade model (persistence/trade_model.py)
    """
    pair: str
    side: str
    entry_price: float
    entry_time: datetime
    stake_amount: float
    amount: float
    strategy: str
    exit_type: Optional[str] = None  # ExitType enum
    exit_price: Optional[float] = None
    exit_time: Optional[datetime] = None
    exit_reason: Optional[str] = None
    pnl: float = 0.0
    pnl_pct: float = 0.0
    stop_loss: Optional[float] = None    # trailing stop
    max_rate: Optional[float] = None     # max reached (для trailing)
    min_rate: Optional[float] = None     # min reached (для trailing)
    orders: list = field(default_factory=list)


class ExitType(str, Enum):
    """🔗 freqtrade: enums/exittype.py"""
    ROI = "ROI"
    STOP_LOSS = "STOP_LOSS"
    TRAILING_STOP_LOSS = "TRAILING_STOP_LOSS"
    EXIT_SIGNAL = "EXIT_SIGNAL"
    FORCE_EXIT = "FORCE_EXIT"
    EMERGENCY_EXIT = "EMERGENCY_EXIT"
    PARTIAL_EXIT = "PARTIAL_EXIT"


class OrderBookCache:
    """Кольцевой буфер снапшотов.
    
    🔗 ccxt: ArrayCache (cache.py)
    """
    def __init__(self, maxlen: int = 100):
        self._buf: deque[OrderBookSnapshot] = deque(maxlen=maxlen)
    
    def push(self, snap: OrderBookSnapshot):
        self._buf.append(snap)
    
    def latest(self) -> Optional[OrderBookSnapshot]:
        return self._buf[-1] if self._buf else None
    
    def window(self, n: int) -> list[OrderBookSnapshot]:
        return list(self._buf)[-n:]
    
    @property
    def is_warm(self) -> bool:
        return len(self._buf) >= 10  # минимум 10 тиков
    
    def get(self, pair: str) -> Optional[OrderBookSnapshot]:
        """Последний снапшот для пары (для мульти-пар)."""
        for snap in reversed(self._buf):
            if snap.pair == pair:
                return snap
        return None
```

---

## 🔷 Фаза 1: AbstractOrderBookStrategy — базовый класс

**⏱ 1ч · 🔴 High**

```python
class AbstractOrderBookStrategy(ABC):
    """Базовый класс для Order Book стратегий.
    
    🔗 freqtrade: IStrategy (interface.py)
    """
    
    # Атрибуты (как в IStrategy)
    name: str = ""
    max_open_trades: int = 1
    exit_after_seconds: int = 60
    max_hold_seconds: int = 120
    stoploss: float = -1.0  # -1% hard stop
    
    # Trailing stop (как в freqtrade)
    trailing_stop: bool = False
    trailing_stop_positive: float = 0.3  # 0.3%
    trailing_stop_positive_offset: float = 0.5  # активация при 0.5% профита
    
    # Protections (как в freqtrade)
    protections: list = field(default_factory=lambda: [
        {"method": "Cooldown", "stop_duration_candles": 5},
    ])
    
    @abstractmethod
    def analyze(self, snap: OrderBookSnapshot, cache: OrderBookCache) -> Optional[OrderBookSignal]:
        """Главный метод: оценить тик стакана → сигнал или None.
        
        🔗 freqtrade: populate_entry_trend() + populate_indicators()
        """
        ...
    
    def confirm_trade_entry(self, signal: OrderBookSignal) -> bool:
        """Gatekeeper: подтвердить вход.
        
        🔗 freqtrade: IStrategy.confirm_trade_entry()
        """
        return True
    
    def custom_exit(self, trade: Trade, snap: OrderBookSnapshot, cache: OrderBookCache) -> Optional[str]:
        """Кастомный сигнал выхода.
        
        🔗 freqtrade: IStrategy.custom_exit()
        Возвращает строку-причину или None.
        """
        return None
    
    def custom_stoploss(self, trade: Trade, current_price: float) -> float:
        """Кастомный стоп-лосс (динамический).
        
        🔗 freqtrade: IStrategy.custom_stoploss()
        """
        return self.stoploss  # fallback
    
    def custom_stake_amount(self, trade: Trade, 
                           proposed_stake: float,
                           free_balance: float) -> float:
        """Кастомный размер ставки.
        
        🔗 freqtrade: IStrategy.custom_stake_amount()
        """
        return proposed_stake  # fallback
```

---

## 🔷 Фаза 2: Стратегия 1 — Imbalance Scalping

**⏱ 2-3ч · 🔴 High**

### 2.1 Логика

**Суть:** Ловим момент, когда одна сторона стакана (bid или ask) резко становится значительно больше другой.

**Сигнал BUY:**
```
1. imbalance > IMBALANCE_THRESHOLD (0.65)    — bid > ask на 65%+
2. bid_volume вырос > SURGE_PCT (20%) за 5 тиков — всплеск объёма
3. spread < MAX_SPREAD (0.05%)               — узкий спред
4. Подтверждение: 3 тика подряд imbalance > 0.55
5. Не iceberg: объём 1-го уровня ≤ 5x объём 2-го
```

**Сигнал SELL:**
```
1. imbalance < (1 - IMBALANCE_THRESHOLD) (0.35) — ask > bid
2. ask_volume вырос > SURGE_PCT (20%) за 5 тиков
3. spread < MAX_SPREAD
4. Подтверждение: 3 тика подряд imbalance < 0.45
5. Не iceberg
```

**Выход:**
```
Exit Pipeline (приоритет):
  1. Strategy custom_exit: imbalance нормализовался (< 0.55 для BUY)
  2. Max hold time: 120 секунд
  3. Trailing stop: активация при 0.5% профита, стоп = 0.3%
  4. Hard stop: -1%
```

### 2.2 Параметры

| Параметр | Значение | freqtrade-аналог |
|----------|----------|-----------------|
| `imbalance_threshold` | 0.65 | — |
| `surge_pct` | 20.0 | — |
| `confirmation_ticks` | 3 | — |
| `max_spread_pct` | 0.05 | SpreadFilter |
| `exit_after_seconds` | 60 | minimal_roi |
| `max_hold_seconds` | 120 | — |
| `stoploss` | -1.0 | stoploss |
| `trailing_stop` | True | trailing_stop |
| `trailing_stop_positive` | 0.3 | trailing_stop_positive |
| `trailing_stop_positive_offset` | 0.5 | trailing_stop_positive_offset |
| `cooldown_seconds` | 120 | Cooldown protection |

### 2.3 Реализация

```python
class ImbalanceScalpingStrategy(AbstractOrderBookStrategy):
    """Стратегия 1: Торговля по дисбалансу стакана.
    
    🔗 freqtrade: каждая стратегия = отдельный .py файл с IStrategy-интерфейсом
    🔗 ccxt: использует OrderBook из ccxt Pro (bids/asks как ArrayCache)
    """
    
    name = "imbalance_scalping"
    
    def __init__(self, config: dict):
        self.imbalance_threshold = config.get("imbalance_threshold", 0.65)
        self.surge_pct = config.get("surge_pct", 20.0)
        self.confirmation_ticks = config.get("confirmation_ticks", 3)
        self.max_spread_pct = config.get("max_spread_pct", 0.05)
        self.exit_after_seconds = config.get("exit_after_seconds", 60)
        self.max_hold_seconds = config.get("max_hold_seconds", 120)
        self.stoploss = config.get("stoploss", -1.0)
        self.trailing_stop = config.get("trailing_stop", True)
        self.trailing_stop_positive = config.get("trailing_stop_positive", 0.3)
        self.trailing_stop_positive_offset = config.get("trailing_stop_positive_offset", 0.5)
    
    def analyze(self, snap: OrderBookSnapshot, cache: OrderBookCache) -> Optional[OrderBookSignal]:
        """🔗 freqtrade: populate_indicators() + populate_entry_trend()"""
        
        # Защита: спред
        if snap.spread_pct > self.max_spread_pct:
            return None
        
        # Защита: iceberg
        if self._is_iceberg(snap):
            return None
        
        # Моментальный дисбаланс
        imb = snap.imbalance
        window = cache.window(self.confirmation_ticks + 2)
        if len(window) < self.confirmation_ticks:
            return None
        
        # Объём за окно
        surge_bid = self._volume_surge(window, "bid")
        surge_ask = self._volume_surge(window, "ask")
        
        # BUY
        if imb > self.imbalance_threshold and \
           surge_bid > self.surge_pct and \
           self._confirm_trend(window, 0.55, "bid"):
            return OrderBookSignal(
                pair=snap.pair,
                side="BUY",
                price=snap.ask_price,  # покупаем по лучшему ask
                strategy_name=self.name,
                confidence=min(imb, 0.95),
                reason=f"imb={imb:.3f} surge={surge_bid:.1f}%",
                exit_after_seconds=self.exit_after_seconds,
                entry_tag="imbalance_buy",
            )
        
        # SELL
        if (1 - imb) > self.imbalance_threshold and \
           surge_ask > self.surge_pct and \
           self._confirm_trend(window, 0.45, "ask"):
            return OrderBookSignal(
                pair=snap.pair,
                side="SELL",
                price=snap.bid_price,  # продаём по лучшему bid
                strategy_name=self.name,
                confidence=min(1 - imb, 0.95),
                reason=f"imb={imb:.3f} surge={surge_ask:.1f}%",
                exit_after_seconds=self.exit_after_seconds,
                entry_tag="imbalance_sell",
            )
        
        return None
    
    def custom_exit(self, trade: Trade, snap: OrderBookSnapshot, 
                    cache: OrderBookCache) -> Optional[str]:
        """Выход при нормализации дисбаланса.
        
        🔗 freqtrade: IStrategy.custom_exit()
        """
        imb = snap.imbalance
        if trade.side == "BUY" and imb < 0.55:
            return "imbalance_normalized"
        if trade.side == "SELL" and imb > 0.45:
            return "imbalance_normalized"
        return None
    
    def _is_iceberg(self, snap: OrderBookSnapshot) -> bool:
        """Обнаружение iceberg: 1-й уровень в 5x+ больше 2-го.
        
        🔗 ccxt: OrderBook.limit() — смотрим глубину
        """
        if len(snap.bids) >= 2:
            if snap.bids[0][1] > snap.bids[1][1] * 5 and snap.bids[1][1] > 0:
                return True
        if len(snap.asks) >= 2:
            if snap.asks[0][1] > snap.asks[1][1] * 5 and snap.asks[1][1] > 0:
                return True
        return False
    
    def _volume_surge(self, window: list, side: str) -> float:
        """% изменения объёма за окно."""
        if len(window) < 2: return 0.0
        vol_0 = window[0].total_bid_volume if side == "bid" else window[0].total_ask_volume
        vol_n = window[-1].total_bid_volume if side == "bid" else window[-1].total_ask_volume
        if vol_0 <= 0: return 0.0
        return (vol_n - vol_0) / vol_0 * 100
    
    def _confirm_trend(self, window: list, threshold: float, side: str) -> bool:
        """Дисбаланс держится N тиков подряд."""
        recent = window[-self.confirmation_ticks:]
        for snap in recent:
            if side == "bid" and snap.imbalance < threshold:
                return False
            if side == "ask" and snap.imbalance > (1 - threshold):
                return False
        return True
```

---

## 🔷 Фаза 3: Стратегия 2 — Spread Capture (Market Making Lite)

**⏱ 2-3ч · 🟡 Medium**

### 3.1 Логика

**Суть:** Ставим лимитные ордера по текущему bid и ask, зарабатываем на спреде. Ждём когда наш ордер исполнят.

**Отличие от классического MM:** 
- Не держим позицию дольше N секунд
- Не инвентаризируем (не хеджируем)
- Только virtual режим (имитация лимитных ордеров)

**Сигнал (вход в позицию):**
```
1. spread > MIN_SPREAD (0.02%) — спред достаточно широкий для профита
2. spread < MAX_SPREAD (0.10%) — не во время волатильности
3. bid_volume > MIN_VOLUME (1.0 BTC) — достаточно ликвидности
4. Объём на уровне достаточный: top5_bid_volume > MIN_LEVEL_VOLUME
5. Нет тренда: imbalance между 0.45-0.55 (рынок нейтрален)
```

**Варианты:**
- BUY: входим по bid, ждём исполнения → через N сек выходим по ask
- SELL: входим по ask, ждём исполнения → через N сек выходим по bid

### 3.2 Параметры

| Параметр | Значение | Описание |
|----------|----------|----------|
| `min_spread_pct` | 0.02 | Минимальный спред для входа |
| `max_spread_pct` | 0.10 | Максимальный спред (не торгуем в волатильность) |
| `min_volume_btc` | 1.0 | Минимальный объём на уровне |
| `neutral_imbalance_low` | 0.45 | Нижняя граница нейтрального рынка |
| `neutral_imbalance_high` | 0.55 | Верхняя граница нейтрального рынка |
| `exit_after_seconds` | 30 | Выход через 30 секунд |
| `stoploss` | -0.5 | Жёсткий стоп -0.5% |
| `trailing_stop` | True | Trailing stop |
| `confirmation_ticks` | 2 | Подтверждение стабильности |

### 3.3 Реализация

```python
class SpreadCaptureStrategy(AbstractOrderBookStrategy):
    """Стратегия 2: Ловля спреда / Market Making Lite.
    
    🔗 freqtrade: похожа на check_depth_of_market() + create_order
    """
    
    name = "spread_capture"
    
    def __init__(self, config: dict):
        self.min_spread_pct = config.get("min_spread_pct", 0.02)
        self.max_spread_pct = config.get("max_spread_pct", 0.10)
        self.min_volume_btc = config.get("min_volume_btc", 1.0)
        self.neutral_imb_low = config.get("neutral_imbalance_low", 0.45)
        self.neutral_imb_high = config.get("neutral_imbalance_high", 0.55)
        self.exit_after_seconds = config.get("exit_after_seconds", 30)
        self.stoploss = config.get("stoploss", -0.5)
        self.trailing_stop = config.get("trailing_stop", True)
    
    def analyze(self, snap: OrderBookSnapshot, 
                cache: OrderBookCache) -> Optional[OrderBookSignal]:
        
        # Проверка спреда
        if snap.spread_pct < self.min_spread_pct:
            return None
        if snap.spread_pct > self.max_spread_pct:
            return None
        
        # Проверка ликвидности
        if snap.total_bid_volume < self.min_volume_btc:
            return None
        if snap.total_ask_volume < self.min_volume_btc:
            return None
        
        # Нейтральный рынок — нет тренда
        imb = snap.imbalance
        if imb < self.neutral_imb_low or imb > self.neutral_imb_high:
            return None
        
        # Подтверждение: стабильность 2 тика
        window = cache.window(2)
        if len(window) >= 2:
            prev = window[0]
            if abs(snap.imbalance - prev.imbalance) > 0.1:
                return None  # слишком резкое изменение
        
        # Входим ОТ bid (покупаем дёшево)
        buy_signal = OrderBookSignal(
            pair=snap.pair,
            side="BUY",
            price=snap.bid_price,
            strategy_name=self.name,
            confidence=0.5,
            reason=f"spread={snap.spread_pct:.3f}% imb={imb:.2f}",
            exit_after_seconds=self.exit_after_seconds,
            entry_tag="spread_buy",
        )
        
        return buy_signal
    
    def custom_exit(self, trade: Trade, snap: OrderBookSnapshot,
                    cache: OrderBookCache) -> Optional[str]:
        """🔗 freqtrade: custom_exit() — выходим когда спред сузился."""
        # Для spread_capture выходим по таймеру (в _manage_positions)
        return None
```

---

## 🔷 Фаза 4: Стратегия 3 — Order Flow Momentum

**⏱ 2-3ч · 🟡 Medium**

### 4.1 Логика

**Суть:** Отслеживаем активность market orders (агрессивные сделки). Если на ask резко возрастает объём — кто-то покупает по рынку (бычий сигнал). Если на bid — продаёт (медвежий).

**Как определяем агрессивные сделки:** изменение стакана между тиками:
- Если ask объём УМЕНЬШИЛСЯ, а bid НЕ ИЗМЕНИЛСЯ → market buy (съели ask)
- Если bid объём УМЕНЬШИЛСЯ, а ask НЕ ИЗМЕНИЛСЯ → market sell (съели bid)

**Сигнал BUY:**
```
1. ask_volume уменьшился > MIN_EATEN_PCT (10%) за 3 тика
2. bid_volume не изменился или вырос (нет паники на bid)
3. spread < MAX_SPREAD
4. Цена (mid) выросла за 3 тика (подтверждение)
```

**Сигнал SELL:**
```
1. bid_volume уменьшился > MIN_EATEN_PCT (10%) за 3 тика
2. ask_volume не изменился или вырос
3. spread < MAX_SPREAD
4. Цена (mid) упала за 3 тика
```

### 4.2 Параметры

| Параметр | Значение |
|----------|----------|
| `min_eaten_pct` | 10.0 |
| `lookback_ticks` | 3 |
| `min_price_move_pct` | 0.01 |
| `max_spread_pct` | 0.05 |
| `exit_after_seconds` | 45 |
| `stoploss` | -1.0 |
| `trailing_stop` | True |

### 4.3 Реализация

```python
class OrderFlowMomentumStrategy(AbstractOrderBookStrategy):
    """Стратегия 3: Моментум по агрессивным сделкам.
    
    Анализирует, как market orders "съедают" ликвидность со стакана.
    """
    
    name = "order_flow_momentum"
    
    def __init__(self, config: dict):
        self.min_eaten_pct = config.get("min_eaten_pct", 10.0)
        self.lookback_ticks = config.get("lookback_ticks", 3)
        self.min_price_move_pct = config.get("min_price_move_pct", 0.01)
        self.max_spread_pct = config.get("max_spread_pct", 0.05)
        self.exit_after_seconds = config.get("exit_after_seconds", 45)
        self.stoploss = config.get("stoploss", -1.0)
    
    def analyze(self, snap: OrderBookSnapshot, 
                cache: OrderBookCache) -> Optional[OrderBookSignal]:
        
        window = cache.window(self.lookback_ticks + 1)
        if len(window) < self.lookback_ticks + 1:
            return None
        
        if snap.spread_pct > self.max_spread_pct:
            return None
        
        # Считаем "съеденный" объём
        ask_eaten = self._volume_eaten(window, "ask")
        bid_eaten = self._volume_eaten(window, "bid")
        
        # Движение цены
        price_move = self._price_move_pct(window)
        
        # BUY: съели ask (market buy), цена пошла вверх
        if ask_eaten > self.min_eaten_pct and \
           price_move > self.min_price_move_pct:
            return OrderBookSignal(
                pair=snap.pair,
                side="BUY",
                price=snap.ask_price,
                strategy_name=self.name,
                confidence=min(ask_eaten / 100, 0.95),
                reason=f"ask_eaten={ask_eaten:.1f}% price={price_move:+.3f}%",
                exit_after_seconds=self.exit_after_seconds,
                entry_tag="momentum_buy",
            )
        
        # SELL: съели bid (market sell), цена пошла вниз
        if bid_eaten > self.min_eaten_pct and \
           price_move < -self.min_price_move_pct:
            return OrderBookSignal(
                pair=snap.pair,
                side="SELL",
                price=snap.bid_price,
                strategy_name=self.name,
                confidence=min(bid_eaten / 100, 0.95),
                reason=f"bid_eaten={bid_eaten:.1f}% price={price_move:+.3f}%",
                exit_after_seconds=self.exit_after_seconds,
                entry_tag="momentum_sell",
            )
        
        return None
    
    def _volume_eaten(self, window: list, side: str) -> float:
        """% объёма, который "съели" за окно."""
        first = window[0]
        last = window[-1]
        
        if side == "ask":
            vol_first = first.total_ask_volume
            vol_last = last.total_ask_volume
        else:
            vol_first = first.total_bid_volume
            vol_last = last.total_bid_volume
        
        if vol_first <= 0: return 0.0
        return (vol_first - vol_last) / vol_first * 100
    
    def _price_move_pct(self, window: list) -> float:
        """% изменение mid-цены за окно."""
        first = window[0].mid_price
        last = window[-1].mid_price
        if first <= 0: return 0.0
        return (last - first) / first * 100
```

---

## 🔷 Фаза 5: Стратегия 4 — Iceberg Detection

**⏱ 2-3ч · 🟢 Nice**

### 5.1 Логика

**Суть:** Обнаруживаем скрытые ордера (iceberg) по характерному поведению стакана и торгуем в их сторону.

**Признаки iceberg:**
```
1. Один и тот же объём появляется на последовательных уровнях после того, 
   как предыдущий уровень съели (классический iceberg)
2. Аномальный паттерн: bid_volume на уровне N > bid_volume на N+1 в 3x+ раз
3. После "съедания" уровня — цена резко идёт в направлении iceberg
4. Общий объём на одной стороне стабильно растёт, хотя уровни меняются
```

**Сигнал:**
```
Если найден iceberg на bid (кто-то скрыто накапливает):
  → BUY: рынок пойдёт вверх, когда iceberg снимут
Если найден iceberg на ask (кто-то скрыто продаёт):
  → SELL: рынок пойдёт вниз
```

**⚠️ Iceberg сложно детектить на 20-уровневом стакане.** Binance depth20 даёт только 20 цен. Полный стакан (5000 уровней) даёт больше данных, но требует diff-потока. Это стратегия "следующего уровня".

### 5.2 Параметры

| Параметр | Значение |
|----------|----------|
| `iceberg_ratio` | 3.0 |
| `lookback_ticks` | 5 |
| `min_volume_btc` | 0.5 |
| `confirmation_ticks` | 3 |
| `exit_after_seconds` | 90 |

---

## 🔷 Фаза 6: ProtectionManager (из freqtrade)

**⏱ 2ч · 🔴 High**

### 6.1 Четыре защиты

Полностью копируем архитектуру freqtrade ProtectionManager:

```python
class ProtectionManager:
    """🔗 freqtrade: plugins/protectionmanager.py"""
    
    def __init__(self, config):
        self._protections: list[IProtection] = []
        self._load_from_config(config)
    
    def global_stop(self) -> Optional[ProtectionReturn]:
        for p in self._protections:
            if p.has_global_stop:
                result = p.global_stop()
                if result:
                    return result
        return None
    
    def stop_per_pair(self, pair: str) -> Optional[ProtectionReturn]:
        for p in self._protections:
            if p.has_local_stop:
                result = p.stop_per_pair(pair)
                if result:
                    return result
        return None
    
    def on_trade_exit(self, trade: Trade):
        """Обновить статистику после закрытия сделки."""
        for p in self._protections:
            p.on_trade(trade)
```

### 6.2 Защиты

**1. Cooldown:**
```
Блокирует пару на N секунд после выхода из сделки.
Параметры: cooldown_seconds (120)
```
Применение: не даёт повторно войти сразу после убыточной сделки.

**2. LowProfit (PairLock):**
```
Блокирует пару если средний профит за последние N сделок < порога.
Параметры: trade_limit (10), min_avg_profit (0.5%)
```
Применение: пара не работает — отключаем на ней стратегию.

**3. MaxDrawdown:**
```
Блокирует все сделки при просадке > порога за период.
Параметры: max_drawdown_pct (5%), lookback_trades (30)
```
Применение: защита от "кровавой бани" — останавливаем всю торговлю.

**4. StoplossGuard:**
```
Блокирует пару если > 20% сделок закончились стоп-лоссом.
Параметры: trade_limit (10), max_stoploss_ratio (0.20), stop_duration_seconds (300)
```
Применение: рынок слишком волатильный — не торгуем.

---

## 🔷 Фаза 7: Wallets — управление балансом

**⏱ 1ч · 🟡 Medium**

```python
class Wallets:
    """🔗 freqtrade: wallets.py"""
    
    def __init__(self, config):
        self.initial_balance = config.get("initial_balance", 1000.0)
        self.max_open_trades = config.get("max_open_trades", 1)
        self._free_balance = self.initial_balance
        self._locked: dict[str, float] = {}  # pair → locked amount
    
    def get_trade_stake_amount(self, pair: str) -> float:
        """🔗 freqtrade: Wallets.get_trade_stake_amount()
        
        Формула: free_balance / max_open_trades
        """
        if self.max_open_trades <= 0:
            return 0.0
        amount = self._free_balance / self.max_open_trades
        # Min stake check
        min_stake = 10.0  # $10 минимум
        if amount < min_stake:
            return 0.0
        return amount
    
    def lock_stake(self, pair: str, amount: float):
        """Заблокировать средства под сделку."""
        self._free_balance -= amount
        self._locked[pair] = amount
    
    def unlock_stake(self, pair: str, pnl: float):
        """Разблокировать после закрытия сделки."""
        locked = self._locked.pop(pair, 0.0)
        self._free_balance += locked + pnl
    
    @property
    def total_balance(self) -> float:
        return self._free_balance + sum(self._locked.values())
    
    def update_balance(self, traded_pnl: float):
        """Обновить общий баланс."""
        self._free_balance += traded_pnl
```

---

## 🔷 Фаза 8: PairLock — блокировка пар

**⏱ 1ч · 🟡 Medium**

```python
class PairLockManager:
    """🔗 freqtrade: persistence/trade_model.py — PairLock"""
    
    def __init__(self):
        self._locks: dict[str, datetime] = {}
    
    def lock(self, pair: str, until: datetime, reason: str):
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

## 🔷 Фаза 9: WebSocket Fetcher (из ccxt)

**⏱ 2ч · 🔴 High**

```python
class BinanceOrderBookStream:
    """WebSocket поток стакана.
    
    🔗 ccxt Pro: client.py + order_book.py (ArrayCache, snapshot+diff sync)
    
    Binance depth stream: wss://stream.binance.com:9443/ws/<stream>@depth20@100ms
    """
    
    def __init__(self, pairs: list[str]):
        self.pairs = pairs
        self.streams = [f"{p.lower()}@depth20@100ms" for p in pairs]
        self._callback = None
        self._ws = None
    
    async def start(self, callback):
        """🔗 ccxt: Client.connect() + watch()"""
        self._callback = callback
        
        # Binance combined stream
        url = f"wss://stream.binance.com:9443/stream?streams={'/'.join(self.streams)}"
        
        async with aiohttp.ClientSession() as session:
            async with session.ws_connect(url) as ws:
                self._ws = ws
                async for msg in ws:
                    if msg.type == aiohttp.WSMsgType.TEXT:
                        data = json.loads(msg.data)
                        snap = self._parse(data)
                        if snap:
                            await self._callback(snap)
                    elif msg.type == aiohttp.WSMsgType.CLOSED:
                        break
                    elif msg.type == aiohttp.WSMsgType.ERROR:
                        break
    
    def _parse(self, raw: dict) -> Optional[OrderBookSnapshot]:
        """🔗 ccxt: parse_order_book() — нормализация Binance → единый формат."""
        try:
            data = raw.get("data", raw)
            pair = data.get("s", "")
            bids = [(float(p), float(q)) for p, q in data.get("b", [])]
            asks = [(float(p), float(q)) for p, q in data.get("a", [])]
            
            return OrderBookSnapshot(
                pair=pair,
                timestamp=datetime.now(timezone.utc),
                bids=bids,
                asks=asks,
            )
        except (KeyError, ValueError, TypeError):
            return None
    
    async def stop(self):
        if self._ws:
            await self._ws.close()
```

---

## 🔷 Фаза 10: RPC — уведомления (из freqtrade)

**⏱ 1ч · 🟢 Nice**

```python
class RPCManager:
    """🔗 freqtrade: rpc/rpc_manager.py"""
    
    def __init__(self, config):
        self._handlers: list[RPCHandler] = []
        if config.get("telegram_enabled"):
            self._handlers.append(TelegramRPCHandler(config))
    
    def send_msg(self, msg_type: str, data: Any):
        for handler in self._handlers:
            try:
                handler.send(msg_type, data)
            except Exception as e:
                debugPrint(f"[RPC] {handler.name} failed: {e}")


# Типы сообщений:
# - "entry" — вход в сделку
# - "exit" — выход из сделки
# - "stop" — сработала защита
# - "error" — ошибка
# - "status" — статус системы
# - "daily" — дневной отчёт
```

---

## 🔷 Фаза 11: Backtesting — эмуляция стакана

**⏱ 2-3ч · 🟢 Nice**

### 11.1 Проблема

Order Book стратегии **нельзя** бэктестить на свечах. Нужны исторические снапшоты стакана.

### 11.2 Решение

**Вариант A: Binance предоставляет исторические depth снапшоты**
- `GET /api/v3/depth?symbol=BTCUSDT&limit=1000` — можно запрашивать раз в N секунд
- Сохранять в файл → потом воспроизводить

**Вариант B: Симулятор на основе свечей**
```python
class OrderBookSimulator:
    """Генерирует псевдо-стакан из свечей.
    
    Не точный, но позволяет протестировать логику стратегий.
    """
    def __init__(self, candles: list[Candle]):
        self.candles = candles
    
    def generate_snapshots(self) -> list[OrderBookSnapshot]:
        """Из свечи → снапшот с распределением объёма."""
        snapshots = []
        for c in self.candles:
            # Распределяем объём по уровням
            snapshots.append(OrderBookSnapshot(
                pair="SIM",
                timestamp=c.timestamp,
                bids=self._distribute_volume(c.close, c.volume, "bid"),
                asks=self._distribute_volume(c.close, c.volume, "ask"),
            ))
        return snapshots
```

### 11.3 Тестирование

```python
async def test_ob_strategy(strategy: AbstractOrderBookStrategy,
                           snapshots: list[OrderBookSnapshot]):
    """Воспроизвести снапшоты и собрать статистику."""
    engine = OrderBookEngine(...)
    stats = {
        "signals": 0,
        "trades": 0,
        "wins": 0,
        "total_pnl": 0.0,
        "max_drawdown": 0.0,
    }
    
    for snap in snapshots:
        await engine._on_snapshot(snap)
        
        if engine._trades:
            for pair, trade in engine._trades.items():
                stats["trades"] += 1
                if trade.pnl > 0: stats["wins"] += 1
                stats["total_pnl"] += trade.pnl
    
    return stats
```

---

## 🔷 Фаза 12: Frontend — Order Book Dashboard

**⏱ 3-4ч · 🟡 Medium**

### 12.1 Flutter страница

```
/orderbook → OrderBookPage
  ├─ OrderBookVisualizer (глубина стакана)
  │    ├─ Bid bars (зелёные слева)
  │    └─ Ask bars (красные справа)
  ├─ StrategyPanel (выбор стратегии, параметры)
  ├─ TradePanel (текущая позиция, PnL)
  ├─ MetricsBar (imbalance, spread, volume surge)
  └─ HistoryList (последние сделки)
```

### 12.2 API эндпоинты

```python
# Запуск OrderBookEngine
POST /api/v1/orderbook/start
  body: { pair, strategy, params }
  → { run_id, status }

# Статус
GET /api/v1/orderbook/status/{run_id}
  → { pair, strategy, position, pnl, metrics, open_trades }

# Стоп
POST /api/v1/orderbook/stop/{run_id}

# WebSocket live-обновления
WS /api/v1/orderbook/{run_id}/live
  → { type: "snapshot" | "trade" | "metric", data: {...} }
```

### 12.3 Визуализация стакана

```
         BID (зелёный)           │          ASK (красный)
  ┌─────────────────────────────┤──────────────────────────────┐
  │ 67500.00  1.500 ████████████│  ████████  0.800  67510.00  │
  │ 67499.00  0.600 ████████    │  ██████  0.400  67511.00   │
  │ 67498.00  0.200 ██          │  ██  0.100  67512.50       │
  │ 67497.00  0.100 █           │  ░   0.050  67514.00       │
  │ 67495.50  0.080 ░           │  ░   0.030  67515.50       │
  └─────────────────────────────┤──────────────────────────────┘
         Объём bid: 2.480        │  Объём ask: 1.380
            Дисбаланс: 0.642     │  Спред: 0.015%
                   ▲             │
              СИЛЬНЫЙ BUY        │
```

---

## 🗺 Дорожная карта

| Фаза | Что делаем | ⏱ | Приоритет | freqtrade/ccxt референс |
|------|-----------|---|-----------|----------------------|
| **0** | Архитектура OrderBookEngine + модели | 3-4ч | 🔴 | FreqtradeBot, ccxt OrderBook |
| **1** | AbstractOrderBookStrategy | 1ч | 🔴 | IStrategy |
| **2** | **Strategy 1: Imbalance Scalping** | 2-3ч | 🔴 | populate_entry_trend + custom_exit |
| **3** | Strategy 2: Spread Capture | 2-3ч | 🟡 | check_depth_of_market |
| **4** | Strategy 3: Order Flow Momentum | 2-3ч | 🟡 | populate_indicators |
| **5** | Strategy 4: Iceberg Detection | 2-3ч | 🟢 | OrderBook.limit() |
| **6** | ProtectionManager (4 защиты) | 2ч | 🔴 | protectionmanager.py |
| **7** | Wallets | 1ч | 🟡 | wallets.py |
| **8** | PairLock | 1ч | 🟡 | pairlock.py |
| **9** | WebSocket Fetcher (ccxt-style) | 2ч | 🔴 | ccxt Pro client.py |
| **10** | RPC уведомления | 1ч | 🟢 | rpc/rpc_manager.py |
| **11** | Backtesting (эмуляция стакана) | 2-3ч | 🟢 | backtesting.py |
| **12** | Frontend (Flutter) | 3-4ч | 🟡 | — |

**Итого:** ~22-30 часов чистого времени на всё.
**MVP (стратегия 1 + ProtectionManager + WebSocket):** ~10-12 часов.

---

## ⚠️ Риски и анти-паттерны

| Риск | Стратегия |
|------|-----------|
| 🔴 **Spoofing** — ложные ордера, которые убирают до твоего исполнения | 3-тик подтверждение (Confirmation ticks) |
| 🔴 **Флип стакана** — цена разворачивается через 100ms после входа | Trailing stop + Max hold time |
| 🟡 **Iceberg-ордера** — невидимый крупный игрок | Iceberg guard |
| 🟡 **Binance WS разрыв** | Reconnect с exponential backoff |
| 🟡 **Слишком много сигналов** — 50 сделок в час | ProtectionManager + Cooldown |
| 🟢 **Рынок "ушёл"** — тренд, а не флип | Silence mode (LowProfit protection) |
| 🔴 **Future leak** — использование ещё не закрытой свечи | Нет свечей → нет проблемы. Но при эмуляции — shift(1) |
| 🔴 **Глобальный стейт** — состояние стратегии в памяти | PairLock + Wallets — вся БД in-memory для скорости, но логи в БД |
| 🟡 **N+1 запросов** — запрос к API на каждый тик | WebSocket — push, не pull. Нет REST-polling |

---

## 🔧 Интеграция с существующей архитектурой super-app

```diff
 backend/app/services/trading/
+  orderbook/                     # NEW
   engine.py                      # ← НЕ ТРОГАЕМ
   models.py                      # ← + OrderBookSnapshot, OrderBookSignal, Trade
   strategies/                    # ← НЕ ТРОГАЕМ (17 свечных)

 backend/app/api/v1/trading.py    # ← + /orderbook/* эндпоинты
 backend/app/models/trading.py    # ← + OrderbookRun, OrderbookTrade таблицы (в будущем)
```

**Ключевые паттерны, взятые из freqtrade + ccxt:**

| Паттерн | Источник | Где используется |
|---------|----------|-----------------|
| Chain of Responsibility | freqtrade PairListManager | ProtectionManager |
| Template Method + hook | freqtrade IStrategy | AbstractOrderBookStrategy |
| Gatekeeper (confirm_*) | freqtrade IStrategy | confirm_trade_entry |
| Exit pipeline (8 причин) | freqtrade ExitType | ExitType enum |
| Leaky Bucket | ccxt Throttler | WebSocket reconnection |
| Snapshot + diff sync | ccxt OrderBook | OrderBookCache |
| Унифицированная нормализация | ccxt parse_* | _parse() в BinanceOrderBookStream |
| RPC фасад | freqtrade RPCManager | manager.py |
| 4 защиты | freqtrade ProtectionManager | protection_*.py |
