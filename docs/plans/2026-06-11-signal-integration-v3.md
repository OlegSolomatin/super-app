# План: Интеграция Telegram-сигналов + API бирж + Real mode (v3)

> **Цель:** Связать скринеры @brushscreener и @stairscreener с платформой. Сигналы → маппинг на правильный движок (OB или Trading) с правильными параметрами → визуал на фронтенде + уведомления → API ключи бирж → real mode.

**Архитектура:** Telegram cronjob → парсер → маппер → сигнал в Redis + PostgreSQL → pub/sub на фронтенд → вкладка «Сигналы» на TradingPage → кнопка запуска правильного engine с правильными параметрами.

---

**Хранилище данных:**
- **Redis** (уже есть, `REDIS_URL=redis://localhost:6379/0`): real-time сигналы (TTL 7d), pub/sub для фронтенда, последние 50 сигналов
- **PostgreSQL** (уже есть): API ключи (связь с users), история запусков, долгосрочная аналитика

---

| # | Приоритет | Фаза | Время |
|---|-----------|------|-------|
| 1 | 🔴 | Telegram парсеры | ~35 мин |
| 2 | 🔴 | Маппер сигналов → стратегии + Redis pub/sub | ~35 мин |
| 3 | 🟡 | Вкладка «Сигналы» на TradingPage + выбор бота | ~50 мин |
| 4 | 🟡 | Telegram уведомления | ~20 мин |
| 5 | 🟡 | API ключи бирж (бэкенд) | ~40 мин |
| 6 | 🟢 | API ключи (фронтенд — секция API в SettingsPage) | ~35 мин |
| 7 | 🟢 | Stair Climber Strategy | ~45 мин |
| 8 | 🟢 | Real mode | ~30 мин |
| | | **Итого:** | **~4.5 ч** |

---

## 🔴 Фаза 1 — Telegram парсеры

**Файлы:**
- `backend/app/services/signals/telegram_parser.py` — новый модуль
- `backend/app/services/signals/__init__.py` — новый пакет
- `backend/scripts/parse_telegram_signals.py` — cronjob-скрипт
- `backend/app/models/trading_signal.py` — модель для хранения сигналов (PostgreSQL)

**Что:**
- Парсит `t.me/s/brushscreener` и `t.me/s/stairscreener` каждые 3 мин через cronjob
- Извлекает: биржа, пара, price_range, vol_60m, vol_10m, slope (stairs), top_ratio, bot_ratio (brush)
- Сохраняет в PostgreSQL `trading_signals` (история)
- Сохраняет в Redis `signals:latest` — последние 50 сигналов (TTL 7 дней)
- Публикует в Redis Pub/Sub `channel:signal:new` — для real-time фронтенда

**Модель TradingSignal (PostgreSQL):**
```python
class TradingSignal(Base):
    __tablename__ = "trading_signals"
    id: int
    channel: str          # brushscreener / stairscreener
    exchange: str         # Mexc, Gate, Mexc Futures
    pair: str             # WOJAKUSDT, ZESTUSDT
    price_range: float    # 0.6-8.5%
    vol_60m: float        # объём за час
    vol_10m: float        # объём за 10 мин
    slope: Optional[float]        # для лесенок
    top_ratio: Optional[float]    # для ёршиков
    bot_ratio: Optional[float]    # для ёршиков
    mapped_strategy: Optional[str]   # заполняется маппером
    mapped_params: Optional[dict]    # JSON-настройки
    is_processed: bool
    created_at: datetime
```

**Redis структура:**
```
signals:latest → LPUSH (список, LTRIM 50, TTL 604800)
signal:{id} → SET (JSON, TTL 604800)
PUBLISH channel:signal:new {id, pair, ...}
```

**API:**
- `GET /api/v1/trading/signals?limit=20` — список сигналов (из PostgreSQL, последние)
- `GET /api/v1/trading/signals/live?limit=20` — список сигналов (из Redis, последние 50)

---

## 🔴 Фаза 2 — Маппер сигналов → стратегии + Redis pub/sub

**Файлы:**
- `backend/app/services/signals/signal_mapper.py` — новый модуль
- `backend/app/core/cache.py` — добавить Redis pub/sub методы (publish, subscribe)
- `backend/app/services/signals/signal_broadcaster.py` — связка: сигнал → Redis pub/sub → WebSocket

**Что:**
- Определяет тип сигнала по метрикам
- Маппит в {движок, стратегия, endpoint, параметры}
- После маппинга публикует результат в Redis pub/sub
- Фронтенд подписывается через WebSocket/SSE

**Таблица маппинга:**

| Тип | Условие | Движок | Стратегия | Endpoint | Параметры |
|-----|---------|--------|-----------|----------|-----------|
| **Ёршик** 🧹 | Top/Bot ≈ (±30%), Range < 3% | OB | `ers_scalping` | `/orderbook/start` | imbalance=0.5, conf_ticks=2, max_spread=0.1, SL=1.5%, TP=3%, max_hold=120, balance=$10 |
| **Лесенка** 🪜 | Slope > 5, Vol10m/Vol60m > 0.2 | Trading | `stair_climber` | `/trading/runs` | TF=3m, min_conf=0.03, SL=2%, TP=5%, max_trade=$2, lev=3 |
| **Дисбаланс Top** ⬆️ | Bot/Top > 1.5×, Range > 3% | OB | `imbalance_scalping` | `/orderbook/start` | imbalance=0.7, surge=2.0, SL=2%, TP=4% |
| **Дисбаланс Bottom** ⬇️ | Top/Bot > 1.5×, Range > 3% | OB | `imbalance_scalping` | `/orderbook/start` | imbalance=0.7 (short) |
| **Всплеск объёма** 🌊 | Vol10m > Vol60m×0.3, Range < 5% | OB | `order_flow_momentum` | `/orderbook/start` | flow_threshold=1000, min_signals=3, SL=2% |

**Redis pub/sub:**
```python
# cache.py — добавить
async def publish_signal(signal_id: int, data: dict):
    await redis.publish("channel:signal:new", json.dumps({"id": signal_id, **data}))

async def subscribe_signals() -> AsyncIterator[dict]:
    pubsub = redis.pubsub()
    await pubsub.subscribe("channel:signal:new")
    async for message in pubsub.listen():
        if message["type"] == "message":
            yield json.loads(message["data"])
```

**Кросс-биржевая проверка (cross-exchange lookup):**
Когда приходит сигнал с биржи, к которой НЕТ API ключа (например Mexc), маппер:
1. Проверяет, есть ли у пользователя ключи к другим биржам (Binance, Bybit)
2. Если есть — берёт ту же пару (WOJAK/USDT) и проверяет на Binance через fetch_ticker()
3. Сравнивает метрики: цена, объём за 24ч, волатильность
4. Если метрики похожи (цена ±5%, объём не нулевой) — предлагает запустить на Binance
5. В карточке сигнала пишет: «🏛 Сигнал с Mexc — доступно на Binance»

**Алгоритм:**
```python
async def cross_exchange_lookup(signal, user_keys):
    """Ищет альтернативную биржу для сигнала."""
    if signal.exchange in [k.exchange for k in user_keys if k.status == "valid"]:
        return signal.exchange  # Уже есть ключ к этой бирже
    
    for key in user_keys:
        if key.status != "valid":
            continue
        ticker = await fetch_ticker(key.exchange, signal.pair)
        if ticker and ticker.get("volume", 0) > 0:
            return key.exchange  # Нашли альтернативу
    
    return None  # Нет альтернативы
```

**UI на фронтенде:**
```
🔔 WOJAK/USDT              2 мин назад
🏛 Mexc Futures • 📊 Ёршик
⚠️ Ключа к Mexc нет
✅ Доступно на Binance (Vol: $15.2M)
🎯 ers_scalping (OrderBook Engine)
```

**API:**
- `POST /api/v1/trading/signals/{id}/start` — запустить сигнал на правильном движке (определяет по mapped_strategy, вызывает нужный endpoint)
- `GET /api/v1/trading/signals/live/stream` — SSE endpoint для real-time сигналов

---

## 🟡 Фаза 3 — Вкладка «Сигналы» на TradingPage + выбор бота

**Файлы:**
- `app/lib/features/trading/presentation/trading_signals_tab.dart` — НОВЫЙ виджет (целая вкладка)
- `app/lib/features/trading/presentation/trading_page.dart` — добавить 3-й таб
- `app/lib/features/trading/data/trading_repository.dart` — добавить методы: getSignals(), startSignal(), getSignalStream()
- `app/lib/features/trading/presentation/providers/trading_signals_provider.dart` — state management
- `app/lib/features/settings/presentation/settings_page.dart` — добавить секцию «API ключи бирж»

**Что:**
- Третья вкладка `[Запуски] [Сигналы] [История]` на TradingPage
- Список последних 20 сигналов из Redis (через `/trading/signals/live`)
- Автообновление через Redis Pub/Sub → SSE (не polling!)
- Каждый сигнал — карточка с:
  - 🔔 Пара + биржа + время
  - Тип и метрики (Ёршик/Лесенка/Дисбаланс/Всплеск)
  - 🎯 Рекомендованная стратегия + движок (OB/Trading)
  - ⚙️ Рекомендованные параметры
  - **Выбор бота для уведомлений** (Dropdown из _bots — тех же, что в SettingsPage)
  - Кнопка **«🚀 Запустить virtual»**
  - Кнопка **«⚙️ В визард»**

**Дизайн карточки сигнала:**
```
┌─────────────────────────────────────────┐
│ 🔔 WOJAK/USDT              2 мин назад │
│ 🏛 Mexc Futures • 📊 Ёршик             │
│ Range: 2.0% | Vol: 10 227$            │
│ Top/Bot: 0.09 / 0.09                  │
│ ─────────────────────────────────     │
│ 🎯 ers_scalping (OrderBook Engine)    │
│ ⚙️ 1m | SL:1.5% | TP:3% | max:$2    │
│                                        │
│ 📨 Уведомления: [🤖 MyBot ▼]          │
│ ┌──────────┐ ┌──────────┐            │
│ │🚀 Запуск │ │⚙️ Визард │            │
│ └──────────┘ └──────────┘            │
└─────────────────────────────────────────┘
```

**Селектор бота:**
- Dropdown-меню, список из TelegramBotData (те же, что в SettingsPage → API)
- Загружается из `GET /api/v1/settings/telegram-bots`
- Выбранный бот сохраняется в локальное состояние (или в preferences)
- Если ботов нет — показывается предупреждение «Добавьте бота в Настройки → API»

**WebSocket/SSE подключение:**
```dart
class SignalStreamService {
  // Подключается к /api/v1/trading/signals/live/stream
  // Возвращает Stream<TradingSignal>
  // При новом сигнале обновляет список
}
```

---

## 🟡 Фаза 4 — Telegram уведомления

**Файлы:**
- `backend/app/services/signals/notification_bot.py`
- `backend/app/api/v1/settings.py` — если нужно обновить эндпоинты ботов

**Что:**
- При новом сигнале отправляет уведомление в Telegram
- Использует выбранного бота (из сигнала или дефолтного из настроек)
- Красивый пост с данными и кнопкой запуска

**Формат:**
```
🔔 WOJAK/USDT — Mexc Futures
📊 Ёршик | Range: 2.0% | Vol: 10 227$
   Top/Bot: 0.09 / 0.09
🎯 ers_scalping (OB Engine)
⚙️ 1m | SL: 1.5% | TP: 3% | balance: $10
🚀 /start_signal_ers WOJAK
```

---

## 🟡 Фаза 5 — API ключи бирж (бэкенд)

**Файлы:**
- `backend/app/models/exchange_key.py` — новая модель
- `backend/app/schemas/exchange_key.py` — Pydantic
- `backend/app/api/v1/exchange_keys.py` — новый роутер
- `backend/app/api/router.py` — добавить роутер
- `backend/app/services/exchange/balance_checker.py` — проверка ключа + баланс

**Что:**
- Модель `ExchangeKey`:
  ```python
  class ExchangeKey(Base):
      id, user_id, exchange (binance/mexc/bybit), api_key_encrypted, api_secret_encrypted
      is_active, status (untested/valid/invalid), balance (float), last_checked_at, created_at
  ```
- Шифрование ключей через Fernet (симметричное шифрование)
- CRUD эндпоинты:
  - `POST /api/v1/exchange-keys` — добавить ключ (шифрует → тестирует → возвращает статус+баланс)
  - `GET /api/v1/exchange-keys` — список (без секретов, только маскированные)
  - `PUT /api/v1/exchange-keys/{id}` — обновить
  - `DELETE /api/v1/exchange-keys/{id}` — удалить
  - `POST /api/v1/exchange-keys/{id}/check` — принудительная проверка

**BalanceChecker:**
```python
class BalanceChecker:
    async def check(self, exchange: str, api_key: str, api_secret: str) -> dict:
        # Binance: ccxt или rest API
        # Mexc: ccxt
        # Возвращает {status, balance, error}
```

**API ключи НЕ трогают существующий TradingEngine — используются только для real mode и отображения баланса.**

---

## 🟢 Фаза 6 — API ключи (фронтенд — секция API в SettingsPage)

**Файлы:**
- `app/lib/features/settings/presentation/settings_page.dart` — добавить подсекцию «Биржи» в секцию API
- `app/lib/features/settings/data/settings_repository.dart` — добавить методы: getKeys(), addKey(), deleteKey(), checkKey()
- `app/lib/features/settings/presentation/providers/exchange_keys_provider.dart`

**Что:**
- В секции `SettingsPage → API` добавляется **вторая подсекция: «Биржи»**
- Первая подсекция — «Telegram боты» (уже есть)
- Вторая подсекция — «API ключи бирж»

**Дизайн:**
```
━━━ API ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📨 Telegram боты (уже есть, не трогаем)
  • MyBot 🤖 [Токен: 12345...]

🔑 API ключи бирж (НОВОЕ)
  ┌─────────────────────────────────────┐
  │ Binance          🟢 $1,245.30       │
  │ API: ***...a1b2                      │
  │ [🔄 Проверить] [🗑 Удалить]         │
  ├─────────────────────────────────────┤
  │ Mexc             🔴 Недействителен  │
  │ [🔄 Проверить] [🗑 Удалить]         │
  ├─────────────────────────────────────┤
  │ [+ Добавить биржу]                  │
  └─────────────────────────────────────┘
```

**Форма добавления:**
- Dropdown: Binance / Mexc / Bybit
- Поле: API Key
- Поле: API Secret (обфусцировано)
- Кнопка «Добавить и проверить» → вызывает POST → показывает статус + баланс

---

## 🟢 Фаза 7 — Stair Climber Strategy

**Файлы:**
- `backend/app/services/trading/strategies/stair_climber.py` — новая стратегия
- `backend/app/services/trading/strategies/__init__.py` — импорт
- `backend/app/services/trading/engine.py` — STRATEGY_REGISTRY
- `backend/app/api/v1/trading.py` — описание стратегии в HARDCODED_STRATEGIES

**Логика стратегии:**
```
1. Найти N последовательных свечей (N=3-5) с:
   - Higher highs + higher lows (восходящая лесенка)
   - ИЛИ Lower highs + lower lows (нисходящая)
   - Объём каждой ступеньки растёт (×1.2+)
2. Рассчитать slope = (price_N - price_0) / N / ATR
3. Если slope > threshold (3.0):
   - Цена подтверждает тренд
4. Вход на откате к EMA(9)
5. Выход: TP по уровню следующей ступеньки, SL по предыдущей
```

**Параметры:**
- `min_steps: int = 3` — минимум ступенек
- `slope_threshold: float = 3.0` — минимальный наклон
- `volume_growth: float = 1.2` — рост объёма
- `pullback_ema: int = 9` — откат к этой EMA

**Описание для API:**
```python
StrategyInfo(
    name="stair_climber",
    description="🪜 Лесенка — поиск ступенчатого роста цены с нарастающим объёмом. Вход на откате к EMA(9). Работает на 1m-3m.",
    type="indicator_based",
    nuances="..."
)
```

---

## 🟢 Фаза 8 — Real mode

**Файлы:**
- `backend/app/services/trading/engine.py` — `run_real()` доработка
- `backend/app/services/trading/exchange/binance.py` — create_order, get_balance
- `backend/app/services/trading/exchange/mexc.py` — если нужно
- `backend/app/services/trading/scheduler.py` — проверка API ключей перед real mode
- `app/lib/features/trading/presentation/trading_signals_tab.dart` — real кнопка

**Что:**
- `run_real()`:
  1. Достаёт API ключ пользователя для выбранной биржи
  2. Проверяет баланс (должен быть ≥ virtual_balance)
  3. Создаёт реальный ордер через exchange API
  4. Выставляет SL лимитный ордер сразу
  5. Мониторит ордер, закрывает по TP/SL
- Валидация перед запуском:
  - Ключ есть? Статус = valid? Баланс ≥ нужного?
  - Не превышен лимит real-запусков (1 на пользователя)
  - Подтверждение через Telegram

**Безопасность:**
- Stop-loss ставится сразу при входе (не надеемся на мониторинг)
- Лимит убытка: max_loss = balance × 0.3
- Максимум 1 real-запуск одновременно
- Все ордеры логируются

---

## 🚫 НЕ меняем

- `app/lib/features/trading/presentation/orderbook_wizard_page.dart` — визард OB
- `app/lib/features/trading/presentation/orderbook_run_detail_page.dart` — детали OB
- `app/lib/features/trading/presentation/trading_page.dart` — только добавляем таб, не рефакторим существующие
- `backend/app/services/trading/orderbook/` — OB Engine
- Существующие стратегии (hammer, supertrend, engulfing и т.д.)
- Тему, хедер, основную навигацию
- Login / Auth / Users
- Hermes / агенты / pipeline

---

## 📊 Поток данных (полный цикл)

```
@brushscreener / @stairscreener
         ↓  (каждые 3 мин)
[cronjob] TelegramParser
         ↓
    ┌────┴────┐
    │         │
    ▼         ▼
 PostgreSQL  Redis (TTL 7d)
 trading_    signals:latest
 signals     signal:{id}
    │         │
    │         ├─→ PUBLISH channel:signal:new
    │         │         ↓
    │         │    SignalMapper.classify()
    │         │    → обновляет mapped_strategy
    │         │    → PUBLISH channel:signal:mapped
    │         │         ↓
    │         │    ┌────┴────┐
    │         │    │         │
    │         │    ▼         ▼
    │         │  Frontend   Telegram Bot
    │         │  (SSE)      (уведомление)
    │         │
    ▼         ▼
[Пользователь нажимает «🚀 Запустить»]
         ↓
POST /trading/signals/{id}/start
         ↓
  ┌──────┴──────┐
  │             │
  ▼             ▼
OB Engine   TradingEngine
ers_scalping stair_climber
imbalance    (или другие)
flow_momentum
  │             │
  └──────┬──────┘
         ↓
   Scheduler → DB (trading_runs / orderbook_runs)
         ↓
   TradingPage → вкладка [Запуски]
```

---

## 💾 Хранилище данных (итог)

```
Redis (уже есть, порт 6379):
  signals:latest    → List, последние 50 сигналов (TTL 7d)
  signal:{id}       → String, JSON сигнала (TTL 7d)
  pub/sub channels:
    channel:signal:new     → новый сигнал
    channel:signal:mapped  → сигнал классифицирован

PostgreSQL (уже есть):
  НОВЫЕ ТАБЛИЦЫ:
    trading_signals   — история сигналов
    exchange_keys     — API ключи бирж (зашифрованные)
  
  СУЩЕСТВУЮЩИЕ (не трогаем):
    users, trading_runs, trading_configs, trading_results
    trading_trades, orderbook_runs, sessions
```

---

Утверждаешь план v3? 🔥
