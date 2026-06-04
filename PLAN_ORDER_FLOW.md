# Order Flow Scalping — План реализации

> **Суть:** Торговля по дисбалансу стакана (order book). Мгновенный вход при появлении крупного объёма на одной стороне, выход через N секунд или при нормализации.

> **Отличие от существующих стратегий:** Все текущие стратегии работают на **закрытых свечах** (history/virtual). Order Flow — на **live тиках стакана**, решения за миллисекунды.

> **Создан:** 04.06.2026

---

## 📋 Легенда

| Метка | Значение |
|-------|----------|
| 🔴 High | Критично для работы стратегии |
| 🟡 Medium | Важно, но не фатально |
| 🟢 Nice | Опциональное улучшение |
| ⏱ | Оценка времени |

---

## 🔷 Фаза 0: Архитектура и данные

### 0.1 Источник данных — Binance WebSocket

```
wss://stream.binance.com:9443/ws/btcusdt@depth20@100ms
```

Формат события (partial book depth):

```json
{
  "e": "depthUpdate",
  "E": 1717488000123,
  "b": [["67500.00", "1.500"]],  // bids: [price, qty]
  "a": [["67510.00", "0.800"]]   // asks: [price, qty]
}
```

**Характеристики:**
- Обновления каждые ~100ms (реально 50-200ms)
- 20 лучших цен на каждую сторону
- На паре BTCUSDT типичный спред ~0.01-0.05%

### 0.2 Модели данных

```python
@dataclass
class OrderBookSnapshot:
    """Снапшот стакана в момент времени."""
    pair: str
    timestamp: datetime
    bids: list[tuple[float, float]]  # [(price, qty), ...] sorted desc
    asks: list[tuple[float, float]]  # [(price, qty), ...] sorted asc

    @property
    def bid_volume(self) -> float:
        return sum(q for _, q in self.bids)

    @property
    def ask_volume(self) -> float:
        return sum(q for _, q in self.asks)

    @property
    def imbalance(self) -> float:
        """Дисбаланс: >1.5 = бычий, <0.7 = медвежий."""
        total = self.bid_volume + self.ask_volume
        if total == 0: return 1.0
        return self.bid_volume / total  # 0.0–1.0

    @property
    def spread(self) -> float:
        """Текущий спред в %."""
        best_bid = self.bids[0][0] if self.bids else 0
        best_ask = self.asks[0][0] if self.asks else 0
        mid = (best_bid + best_ask) / 2
        return (best_ask - best_bid) / mid * 100 if mid > 0 else 999

    @property
    def top_5_bid_volume(self) -> float:
        return sum(q for _, q in self.bids[:5])

    @property
    def top_5_ask_volume(self) -> float:
        return sum(q for _, q in self.asks[:5])
```

```python
@dataclass
class OrderFlowSignal:
    """Сигнал от Order Flow стратегии."""
    side: str  # BUY / SELL
    price: float
    confidence: float  # 0.0–1.0
    imbalance: float
    reason: str  # debug: почему сработало
```

```python
@dataclass
class OrderFlowMetrics:
    """Метрики за окно N тиков."""
    avg_imbalance: float
    imbalance_std: float
    bid_volume_delta: float     # изменение объёма bid за окно
    ask_volume_delta: float     # изменение объёма ask за окно
    trade_count: int            # сколько раз менялся стакан
    price_change_pct: float     # изменение mid-цены за окно
```

### 0.3 Сравнение: Order Flow vs свечные стратегии

| Параметр | Свечные стратегии | Order Flow Scalping |
|----------|------------------|-------------------|
| **Данные** | OHLCV свечи (1m-1d) | Order book depth (100ms) |
| **Вход** | На закрытии свечи | В момент изменения стакана |
| **Выход** | SL/TP (фикс %) | Через N секунд или при нормализации |
| **Частота** | 1-30 сигналов/день | 5-50 сигналов/час |
| **Длительность сделки** | Часы-дни | Секунды-минуты |
| **Риск** | Трендовый разворот | Spoofing, флип стакана |
| **Спред** | Не важен (1h TF) | Критичен (< 0.05%) |
| **Режим работы** | history / virtual | Только virtual (live) |

---

## 🔷 Фаза 1: Backend — OrderBookFetcher (WebSocket)

**⏱ 2-3ч · 🔴 High**

### 1.1 Создать `backend/app/services/trading/orderbook/`

```
backend/app/services/trading/orderbook/
├── __init__.py
├── fetcher.py          # WebSocket клиент → снапшоты
├── cache.py            # Кольцевой буфер последних N снапшотов
└── metrics.py          # Расчёт метрик по окну снапшотов
```

### 1.2 `fetcher.py` — WebSocket клиент

```python
import asyncio, json, logging
from datetime import datetime, timezone
from typing import Callable
import websockets

class OrderBookFetcher:
    """Подключается к Binance WS и отдаёт OrderBookSnapshot."""

    STREAMS = {
        "BTCUSDT": "btcusdt@depth20@100ms",
        "ETHUSDT": "ethusdt@depth20@100ms",
        # расширяемый список
    }

    def __init__(self, on_snapshot: Callable):
        self._on_snapshot = on_snapshot
        self._ws = None
        self._running = False

    async def start(self, pairs: list[str]):
        """Подключиться к Binance WS."""
        streams = [self.STREAMS[p] for p in pairs if p in self.STREAMS]
        url = f"wss://stream.binance.com:9443/stream?streams={'/'.join(streams)}"
        self._running = True
        async with websockets.connect(url) as ws:
            self._ws = ws
            while self._running:
                msg = await ws.recv()
                data = json.loads(msg)
                snapshot = self._parse(data)
                if snapshot:
                    self._on_snapshot(snapshot)

    def _parse(self, data: dict) -> Optional[OrderBookSnapshot]:
        """Преобразовать Binance raw → OrderBookSnapshot."""
        ...

    async def stop(self):
        self._running = False
        if self._ws:
            await self._ws.close()
```

### 1.3 `cache.py` — Кольцевой буфер

```python
from collections import deque
from app.services.trading.models.orderbook import OrderBookSnapshot

class OrderBookCache:
    """Хранит последние N снапшотов для расчёта метрик."""

    def __init__(self, maxlen: int = 50):
        self._buf: deque[OrderBookSnapshot] = deque(maxlen=maxlen)

    def push(self, snap: OrderBookSnapshot):
        self._buf.append(snap)

    def latest(self) -> Optional[OrderBookSnapshot]:
        return self._buf[-1] if self._buf else None

    def window(self, n: int = 10) -> list[OrderBookSnapshot]:
        """Последние N снапшотов."""
        return list(self._buf)[-n:]

    @property
    def is_warm(self) -> bool:
        """Минимум 10 снапшотов для первой оценки."""
        return len(self._buf) >= 10
```

### 1.4 `metrics.py` — Расчёт метрик

```python
class OrderFlowMetricsCalculator:
    """Считает метрики по окну снапшотов."""

    def imbalance_trend(self, window: list[OrderBookSnapshot]) -> float:
        """Средний дисбаланс за окно."""
        if not window: return 1.0
        return sum(s.imbalance for s in window) / len(window)

    def volume_surge(self, window: list[OrderBookSnapshot],
                     side: str = "bid") -> float:
        """Всплеск объёма — % изменения за последние N тиков."""
        if len(window) < 2: return 0.0
        vol_prev = getattr(window[0], f"{side}_volume")
        vol_curr = getattr(window[-1], f"{side}_volume")
        if vol_prev <= 0: return 0.0
        return (vol_curr - vol_prev) / vol_prev * 100

    def spread_ok(self, snap: OrderBookSnapshot,
                  max_spread_pct: float = 0.05) -> bool:
        """Проверка, что спред не разъехался."""
        return snap.spread <= max_spread_pct
```

---

## 🔷 Фаза 2: Backend — OrderFlowStrategy (логика)

**⏱ 2-3ч · 🔴 High**

### 2.1 Сигналы — что ловим

**Сигнал BUY:**
```
1. bid_volume / total_volume > IMBALANCE_THRESHOLD (0.65)
2. spread < MAX_SPREAD (0.05%)
3. bid_volume вырос > SURGE_THRESHOLD (20%) за последние 5 тиков
4. Цена (mid) ≥ лучший bid (не даём себя обмануть — не покупаем выше рынка)
```

**Сигнал SELL:**
```
1. ask_volume / total_volume > IMBALANCE_THRESHOLD (0.65)
2. spread < MAX_SPREAD
3. ask_volume вырос > SURGE_THRESHOLD (20%) за последние 5 тиков
4. Цена (mid) ≤ лучший ask
```

**Выход по таймеру:**
```
Выход через EXIT_SECONDS (30-120 сек) от входа.
Без SL/TP — цена за 30-120 сек либо пойдёт в твою сторону, либо нет.
```

### 2.2 Механизм защиты (critical)

| # | Защита | Как работает | Почему |
|---|--------|-------------|--------|
| 1 | 🔒 **Cooldown** | После выхода — пауза N секунд (60-300) | Не даёт повторно войти в тот же памп |
| 2 | 🛡 **Min spread check** | Торгуем только если спред < 0.05% | Широкий спред = высокая волатильность = флип |
| 3 | 🧹 **Spoofing guard** | Сигнал засчитывается только если дисбаланс держится ≥3 тиков подряд | Крупные ордера могут быть ложными (spoof) |
| 4 | 📏 **Max position** | 1 открытая позиция на пару | Не удваиваемся |
| 5 | ⏰ **Max hold time** | Сделка автоматически закрывается через MAX_HOLD_SEC (120) | Не держим убыток |
| 6 | 🔇 **Silence mode** | Если за последние 30 сделок winrate < 20% — остановка на 1 час | Стратегия не работает в данном рынке |
| 7 | 📊 **Volume floor** | Минимальный объём на уровне bid/ask > 0.5 BTC | Не торгуем пустые стаканы |
| 8 | 🧊 **Iceberg guess** | Если объём на 1 уровне >> объём на 2-м (5x+) — скорее всего iceberg, не входить | Не даём себя развернуть |

### 2.3 Параметры стратегии

```python
class OrderFlowScalpingConfig:
    # Сигнал
    imbalance_threshold: float = 0.65    # 65% объёма на одной стороне
    surge_threshold_pct: float = 20.0     # всплеск объёма 20%+ за окно
    confirmation_ticks: int = 3           # сколько тиков держится дисбаланс

    # Выход
    exit_seconds: int = 60                # через N сек после входа
    max_hold_seconds: int = 120           # макс. удержание

    # Защита
    cooldown_seconds: int = 120           # пауза после сделки
    max_spread_pct: float = 0.05          # макс. спред
    min_volume_btc: float = 0.5           # мин. объём на уровне
    max_open_positions: int = 1           # макс. открытых позиций

    # Silence detection
    silence_min_trades: int = 30
    silence_winrate_threshold: float = 0.2
    silence_duration_minutes: int = 60
```

### 2.4 АРХИТЕКТУРНОЕ РЕШЕНИЕ — отдельный движок

**Order Flow Scalping НЕ может использовать существующий `engine.py`** (который работает на свечах).

Создаётся **отдельный движок**:

```python
class OrderFlowEngine:
    """Live-движок для Order Flow Scalping.
    
    - Не использует свечи
    - Не использует DataLoader
    - Работает только в virtual режиме (нет реальных API-ключей)
    - Своя логика открытия/закрытия
    """

    def __init__(self, config: TradingConfig):
        self.config = config
        self.fetcher = OrderBookFetcher(on_snapshot=self._on_snapshot)
        self.cache = OrderBookCache()
        self.metrics_calc = OrderFlowMetricsCalculator()
        self._position: Optional[Trade] = None
        self._cooldown_until: Optional[datetime] = None
        self._slience_mode = False
        self._trade_history: list[Trade] = []
        self._entry_prices: list[float] = []  # для entry tracking

    async def start(self):
        """Точка входа: запуск WS → бесконечный цикл обработки."""
        # Запускаем WS в фоне
        task = asyncio.create_task(
            self.fetcher.start([self.config.pair])
        )
        # Параллельно отслеживаем время удержания
        await self._position_loop()

    async def _on_snapshot(self, snap: OrderBookSnapshot):
        """Callback от WebSocket — каждый новый снапшот."""
        if self._slience_mode: return
        if self._cooldown_until and datetime.now(timezone.utc) < self._cooldown_until: return

        self.cache.push(snap)
        if not self.cache.is_warm: return

        signal = self._evaluate()
        if signal:
            self._execute(signal)

    def _evaluate(self) -> Optional[OrderFlowSignal]:
        """Главная логика — оценить ситуацию в стакане."""
        window = self.cache.window(5)
        latest = window[-1]

        # Защита 2: спред
        if not self.metrics_calc.spread_ok(latest, self.config.max_spread_pct):
            return None

        # Защита 7: объём
        if latest.bid_volume < self.config.min_volume_btc and \
           latest.ask_volume < self.config.min_volume_btc:
            return None

        # Защита 8: iceberg guess
        if self._is_iceberg(latest):
            return None

        # Основной сигнал
        imbalance = latest.imbalance
        surge_bid = self.metrics_calc.volume_surge(window, "bid")
        surge_ask = self.metrics_calc.volume_surge(window, "ask")

        # BUY: bid доминирует + всплеск bid
        if imbalance > self.config.imbalance_threshold and \
           surge_bid > self.config.surge_threshold_pct:
            # Защита 3: подтверждение
            if self._confirm_trend(window, "bid"):
                return OrderFlowSignal(
                    side="BUY", price=latest.bids[0][0],
                    confidence=min(imbalance, 0.95),
                    imbalance=imbalance,
                    reason=f"bid_vol={latest.bid_volume:.3f} surge={surge_bid:.1f}%"
                )

        # SELL: ask доминирует + всплеск ask
        if (1 - imbalance) > self.config.imbalance_threshold and \
           surge_ask > self.config.surge_threshold_pct:
            if self._confirm_trend(window, "ask"):
                return OrderFlowSignal(
                    side="SELL", price=latest.asks[0][0],
                    confidence=min(1 - imbalance, 0.95),
                    imbalance=imbalance,
                    reason=f"ask_vol={latest.ask_volume:.3f} surge={surge_ask:.1f}%"
                )

        return None

    def _confirm_trend(self, window: list, side: str) -> bool:
        """Защита 3: дисбаланс держится ≥3 тиков."""
        if len(window) < self.config.confirmation_ticks:
            return False
        recent = window[-self.config.confirmation_ticks:]
        for snap in recent:
            if side == "bid" and snap.imbalance < 0.55:
                return False
            if side == "ask" and (1 - snap.imbalance) < 0.55:
                return False
        return True

    def _is_iceberg(self, snap: OrderBookSnapshot) -> bool:
        """Защита 8: подозрение на iceberg."""
        if len(snap.bids) >= 2:
            level0 = snap.bids[0][1]
            level1 = snap.bids[1][1]
            if level0 > level1 * 5 and level1 > 0:
                return True
        if len(snap.asks) >= 2:
            level0 = snap.asks[0][1]
            level1 = snap.asks[1][1]
            if level0 > level1 * 5 and level1 > 0:
                return True
        return False

    def _execute(self, signal: OrderFlowSignal):
        """Открыть позицию."""
        # Защита 4: не больше 1 позиции
        if self._position:
            return

        now = datetime.now(timezone.utc)
        self._position = Trade(
            side=signal.side,
            entry_price=signal.price,
            entry_time=now,
            quantity=self.config.initial_balance / signal.price,
            pair=self.config.pair,
            exit_target=None,  # нет TP — выход по таймеру
        )
        logger.info(
            f"[OF] ENTRY {signal.side} {self.config.pair} "
            f"@{signal.price:.2f} | imbalance={signal.imbalance:.3f} | {signal.reason}"
        )

    async def _position_loop(self):
        """Фоновый цикл — следит за открытой позицией и закрывает по таймеру."""
        while True:
            await asyncio.sleep(1)
            if not self._position:
                continue

            now = datetime.now(timezone.utc)
            age = (now - self._position.entry_time).total_seconds()

            # Защита 5: max hold time
            if age >= self.config.max_hold_seconds:
                self._close_position("max_hold", now)

            # Выход по таймеру
            elif age >= self.config.exit_seconds:
                snap = self.cache.latest()
                if snap:
                    exit_price = snap.bids[0][0] if self._position.side == "BUY" \
                                 else snap.asks[0][0]
                    self._close_position("time_exit", now, exit_price)

    def _close_position(self, reason: str, now: datetime,
                        exit_price: Optional[float] = None):
        """Закрыть позицию и обновить статистику."""
        if not self._position:
            return

        snap = self.cache.latest()
        if exit_price is None:
            if self._position.side == "BUY":
                exit_price = snap.bids[0][0] if snap else self._position.entry_price
            else:
                exit_price = snap.asks[0][0] if snap else self._position.entry_price

        pnl_pct = (exit_price - self._position.entry_price) / self._position.entry_price * 100
        if self._position.side == "SELL":
            pnl_pct = -pnl_pct

        self._position.exit_price = exit_price
        self._position.exit_time = now
        self._position.pnl = pnl_pct / 100 * self._position.quantity * self._position.entry_price
        self._position.exit_reason = reason

        # Сохраняем в историю
        self._trade_history.append(self._position)
        logger.info(
            f"[OF] EXIT {self._position.side} {self.config.pair} "
            f"@{exit_price:.2f} | pnl={pnl_pct:+.2f}% | reason={reason}"
        )

        self._position = None
        self._cooldown_until = now + timedelta(seconds=self.config.cooldown_seconds)

        # Защита 6: silence mode
        self._check_silence()

    def _check_silence(self):
        """Защита 6: если winrate < 20% за последние 30 сделок — пауза."""
        recent = self._trade_history[-self.config.silence_min_trades:]
        if len(recent) < self.config.silence_min_trades:
            return
        wins = sum(1 for t in recent if t.pnl > 0)
        wr = wins / len(recent)
        if wr < self.config.silence_winrate_threshold:
            self._slience_mode = True
            logger.warning(
                f"[OF] SILENCE MODE: winrate={wr:.1%} < "
                f"{self.config.silence_winrate_threshold:.0%} "
                f"for last {len(recent)} trades — pausing {self.config.silence_duration_minutes}m"
            )
            # Через N минут выключаем silence
            asyncio.create_task(self._reset_silence())
```

---

## 🔷 Фаза 3: Backend — Интеграция с API

**⏱ 1ч · 🟡 Medium**

### 3.1 Новый эндпоинт

```python
# backend/app/api/v1/trading.py

@router.post("/orderflow/start")
async def start_orderflow(config: OrderFlowConfig):
    """Запустить Order Flow Scalping для пары."""
    engine = OrderFlowEngine(config)
    run_id = await save_run_to_db(config)
    asyncio.create_task(engine.start())
    return {"run_id": run_id, "status": "running"}

@router.get("/orderflow/status/{run_id}")
async def orderflow_status(run_id: str):
    """Текущее состояние: позиция, PnL, метрики."""
    ...

@router.post("/orderflow/stop/{run_id}")
async def stop_orderflow(run_id: str):
    """Остановить Order Flow движок."""
    ...
```

### 3.2 Новая таблица

```sql
CREATE TABLE orderflow_runs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    pair TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'running',
    started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    stopped_at TIMESTAMPTZ,
    total_trades INT DEFAULT 0,
    total_pnl DECIMAL DEFAULT 0,
    win_count INT DEFAULT 0,
    loss_count INT DEFAULT 0,
    silence_triggered BOOLEAN DEFAULT FALSE,
    config JSONB NOT NULL
);

CREATE TABLE orderflow_trades (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    run_id UUID REFERENCES orderflow_runs(id),
    side TEXT NOT NULL,
    entry_price DECIMAL NOT NULL,
    exit_price DECIMAL,
    entry_time TIMESTAMPTZ NOT NULL,
    exit_time TIMESTAMPTZ,
    pnl DECIMAL DEFAULT 0,
    pnl_percent DECIMAL DEFAULT 0,
    exit_reason TEXT,
    imbalance_at_entry DECIMAL,
    reason TEXT
);
```

---

## 🔷 Фаза 4: Frontend — страница Order Flow

**⏱ 2-3ч · 🟡 Medium**

### 4.1 OrderBook визуализация

- **Горизонтальные бары:** bid (зелёный слева) / ask (красный справа)
- **Цифры спреда и дисбаланса** в центре
- **Анимация обновления** каждые ~200ms

```
        BID                  │      ASK
  ┌──────────────────────────┤──────────────────────┐
  │ 67500.00  1.500 ████████│  ██████  0.800  67510.00
  │ 67499.50  0.200 ██      │  ██  0.100  67511.00
  │ 67498.00  0.050 ░       │  ░   0.030  67512.50
  └──────────────────────────┤──────────────────────┘
     Bid Vol: 2.450          │  Ask Vol: 1.200
           Imbalance: 0.671  │  Spread: 0.015%
```

### 4.2 Dashboard метрики

- `💹 Imbalance` — текущий (0->1), цветом
- `📊 Bids / Asks` — объём на каждой стороне
- `⚡ Surge %` — всплеск объёма за окно
- `🟢//🔴 Position` — открыта/закрыта
- `📈 PnL` — за текущий запуск
- `🏆 WinRate` — за запуск

### 4.3 Плитка на главной

```
┌──────────────────────────┐
│ ⚡ Order Flow            │
│ BTCUSDT · Спред 0.015%   │
│ 🔵 Дисбаланс 0.67        │
└──────────────────────────┘
```

---

## 🔷 Фаза 5: Тестирование

**⏱ 1-2ч · 🟡 Medium**

### 5.1 Локальный тест

1. Запустить OrderFlowEngine в тестовом режиме
2. Смотреть логи: приходят ли снапшоты, считаются ли метрики
3. Проверить защиту 3 (confirmation_ticks):
   - Эмуляция 1 тика с дисбалансом → нет сигнала
   - Эмуляция 3+ тиков → сигнал
4. Проверить защиту 5 (max_hold):
   - Открыть позицию → через 120 сек закрывается

### 5.2 Эмуляция spoofing

1. Создать 2 тика с большим объёмом на bid
2. 3-й тик — объём убран
3. Убедиться, что confirmation_ticks блокирует сигнал

### 5.3 Эмуляция silence mode

1. Сделать 30 сделок с убытком
2. Проверить, что silence_mode = True
3. Через N минут сброс

---

## 🗺 Дорожная карта

| Фаза | Что делаем | ⏱ | 🔴 |
|------|-----------|----|----|
| **0** | Архитектура + модели OrderBook | 1ч | 🔴 |
| **1** | OrderBookFetcher + Cache + Metrics | 2-3ч | 🔴 |
| **2** | OrderFlowEngine (логика + защита) | 2-3ч | 🔴 |
| **3** | API эндпоинты + БД | 1ч | 🟡 |
| **4** | Frontend (визуализация стакана) | 2-3ч | 🟡 |
| **5** | Тестирование | 1-2ч | 🟡 |

**Итого:** ~10-13 часов чистого времени.

---

## ⚠️ Известные риски

| Риск | Вероятность | Смягчение |
|------|------------|-----------|
| Binance WS отваливается | 🟡 Средняя | Reconnect с exponential backoff |
| Spoofing (ложные ордера) | 🔴 Высокая | 3-тик подтверждение (защита 3) |
| Флип стакана за 100ms | 🟡 Средняя | Сигнал только при тренде >3 тиков |
| Широкий спред (волатильность) | 🟡 Средняя | Max spread filter (защита 2) |
| Стратегия не работает на данной паре | 🟡 Средняя | Silence mode (защита 6) |
| WS data race / race condition | 🟢 Низкая | asyncio.Lock на позицию |

---

## 🔧 Интеграция с существующей архитектурой

```diff
 backend/app/services/trading/
+  orderbook/                 # NEW: Order Flow модуль
+    __init__.py
+    fetcher.py               # WebSocket → снапшоты
+    cache.py                 # Кольцевой буфер
+    metrics.py               # Метрики дисбаланса
+  orderflow_engine.py        # NEW: Order Flow движок
   engine.py                  # ← НЕ трогать (свечной движок)
   models.py                  # ← НЕ трогать + NEW: OrderBookSnapshot
   strategies/                # ← НЕ трогать (17 стратегий)
```

**Важно:** Order Flow НЕ наследуется от AbstractStrategy, НЕ использует DataLoader, НЕ использует существующий engine.py. Это параллельная система, работающая ТОЛЬКО live (virtual).
