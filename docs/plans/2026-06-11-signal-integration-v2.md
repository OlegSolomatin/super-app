# План: Интеграция Telegram-сигналов + API бирж + Real mode (v2)

> **Цель:** Связать скринеры @brushscreener и @stairscreener с платформой. Сигналы → автоматический запуск на правильном движке (OB или Trading) с правильными параметрами. Визуал на фронтенде. API ключи бирж.

**Архитектура:** Telegram cronjob → парсер → маппер → сигнал в БД → вебсокет/пуш на фронтенд → кнопка запуска → правильный engine (OB или Trading) с правильными параметрами.

---

## 🔧 Два движка — две системы

```
┌─ OrderBookEngine ─────────────────────┐    ┌─ TradingEngine ───────────────┐
│  ers_scalping       ← Ёршик          │    │  stair_climber    ← Лесенка  │
│  imbalance_scalping ← Дисбаланс      │    │  (новая стратегия)           │
│  order_flow_momentum← Всплеск объёма │    │  run_history/virtual/real    │
│  spread_capture                       │    │                              │
│                                       │    │                              │
│  WebSocket depth20                    │    │  OHLCV свечи (1m-3m)        │
│  POST /orderbook/start                │    │  POST /trading/runs          │
└───────────────────────────────────────┘    └──────────────────────────────┘
```

**Важно:** каждый сигнал запускается на **своём** движке с **разными** параметрами. Маппер должен знать, какой endpoint вызывать.

---

## 🔴 Фаза 1 — Telegram парсеры

**Файлы:**
- `backend/app/services/signals/telegram_parser.py` — новый модуль
- `backend/app/models/trading_signal.py` — модель для хранения сигналов в БД
- `backend/app/schemas/trading_signal.py` — Pydantic schema
- `backend/scripts/parse_telegram_signals.py` — cronjob-скрипт
- `backend/app/services/signals/__init__.py`

**Что:**
- Парсит `t.me/s/brushscreener` и `t.me/s/stairscreener` каждые 2-3 мин через cronjob
- Извлекает: биржа, пара, price_range, vol_60m, vol_10m, slope (stairs), top_bot_ratio (brush)
- Сохраняет сигналы в БД `trading_signals` (с дедупликацией по паре + времени)
- API: `GET /api/v1/trading/signals` — последние N сигналов (для фронтенда)

**Модель TradingSignal:**
```python
class TradingSignal(Base):
    __tablename__ = "trading_signals"
    id, channel, exchange, pair, price_range, vol_60m, vol_10m
    slope (nullable), top_ratio (nullable), bot_ratio (nullable)
    mapped_strategy (nullable)  # заполняется маппером
    mapped_params (nullable)    # JSON-настройки
    is_processed: bool          # отправлено/запущено
    created_at
```

---

## 🔴 Фаза 2 — Маппер сигналов → стратегии + параметры

**Файлы:**
- `backend/app/services/signals/signal_mapper.py`
- `backend/app/services/signals/telegram_parser.py` — добавить pub/sub через Redis
- `backend/app/core/cache.py` — добавить Redis pub/sub методы — новый модуль

**Что:**
- Определяет тип сигнала и маппит в стратегию + endpoint + параметры

**Маппинг (таблица решений):**

| Тип | Условие | Движок | Стратегия | Endpoint | Параметры |
|-----|---------|--------|-----------|----------|-----------|
| **Ёршик** | Top/Bot ~равны (±30%), Range < 3% | OB | `ers_scalping` | `/orderbook/start` | TF=1m, conf_ticks=2, max_spread=0.1, SL=1.5%, TP=3%, max_hold=120с, balance=$10 |
| **Лесенка** | Slope > 5, Vol10m растёт > Vol60m×0.2 | Trading | `stair_climber` | `/trading/runs` | TF=3m, min_confidence=0.03, SL=2%, TP=5%, max_trade=$2, leverage=3 |
| **Дисбаланс Top** | Bot/Top > 1.5×, Range > 3% | OB | `imbalance_scalping` | `/orderbook/start` | imbalance_threshold=0.7, surge_pct=2.0, SL=2%, TP=4% |
| **Дисбаланс Bottom** | Top/Bot > 1.5×, Range > 3% | OB | `imbalance_scalping` | `/orderbook/start` | imbalance_threshold=0.7 (short), surge_pct=2.0 |
| **Всплеск объёма** | Vol10m > Vol60m×0.3, Range < 5% | OB | `order_flow_momentum` | `/orderbook/start` | flow_threshold=1000, min_signals=3, SL=2%, TP=4% |

**Метод:**
```python
class SignalMapper:
    @staticmethod
    def classify(signal: TradingSignal) -> MappingResult:
        """Определяет стратегию и параметры по данным сигнала."""
    
    @staticmethod
    def generate_recommendation(signal: TradingSignal) -> str:
        """Человеческая рекомендация для уведомления."""
```

---

## 🟡 Фаза 3 — Сигналы на странице трейдинга (фронтенд)

**Файлы:**
- `app/lib/features/trading/presentation/trading_signals_tab.dart` — НОВЫЙ виджет
- `app/lib/features/trading/presentation/trading_page.dart` — добавить таб
- `app/lib/features/trading/data/trading_repository.dart` — добавить метод getSignals()
- `app/lib/features/trading/presentation/providers/trading_signals_provider.dart` — state

**Что:**
- Третья вкладка на TradingPage: `[Запуски] [Сигналы] [История]`
- Список последних сигналов (10-20) с данными и рекомендациями
- Каждый сигнал — карточка:
  - 🔔 Пара + биржа + время
  - Определённый тип (Ёршик/Лесенка/Дисбаланс/Всплеск)
  - Метрики (Range, Vol, Slope/TopBot)
  - Рекомендованная стратегия с параметрами
  - Кнопка **«🚀 Запустить virtual»** — сразу запускает на правильном движке
  - Кнопка **«⚙️ В визард»** — открывает визард с заполненными параметрами

**Дизайн карточки сигнала:**
```
┌─────────────────────────────────────────────┐
│ 🔔 WOJAK/USDT              2 мин назад      │
│ 🏛 Mexc Futures • 📊 Ёршик                  │
│ Range: 2.0% | Vol: 10 227$                 │
│ Top/Bot: 0.09 / 0.09                       │
│ ─────────────────────────────────────       │
│ 🎯 ers_scalping (OrderBook Engine)          │
│ ⚙️ 1m | SL:1.5% | TP:3% | max:$2          │
│ ┌──────────┐ ┌──────────┐                  │
│ │🚀 Запуск │ │⚙️ Визард │                  │
│ └──────────┘ └──────────┘                  │
└─────────────────────────────────────────────┘
```

**API для фронтенда:**
- `GET /api/v1/trading/signals?limit=20` — список сигналов
- `GET /api/v1/trading/signals/{id}` — детали сигнала
- `POST /api/v1/trading/signals/{id}/start` — запустить сигнал на правильном движке

---

## 🟡 Фаза 4 — Telegram уведомления

**Файлы:**
- `backend/app/services/signals/notification_bot.py`

**Что:**
- При новом сигнале (или когда маппер его классифицировал) — уведомление в Telegram Олегу
- Дублирует карточку из фронтенда

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
- `backend/app/models/exchange_key.py`
- `backend/app/schemas/exchange_key.py`
- `backend/app/api/v1/exchange_keys.py`
- `backend/app/api/router.py`
- `backend/app/services/exchange/balance_checker.py`

**Что:**
- Модель `ExchangeKey` (id, user_id, exchange, api_key_encrypted, api_secret_encrypted, is_active, status, balance)
- Шифрование ключей (Fernet)
- CRUD эндпоинты
- При сохранении — тестовый запрос к бирже, возврат статуса + баланса

---

## 🟢 Фаза 6 — API ключи (фронтенд)

**Файлы:**
- `app/lib/features/settings/presentation/exchange_keys_page.dart`
- `app/lib/features/settings/data/exchange_key_repository.dart`
- `app/lib/features/settings/presentation/settings_page.dart` — пункт меню
- `app/lib/router/router_config.dart` — маршрут

**Что:**
- Страница настроек со списком ключей + формой добавления
- Статус 🟢/🔴/⚪ для каждого ключа
- Отображение баланса кошелька

---

## 🟢 Фаза 7 — Stair Climber Strategy

**Файлы:**
- `backend/app/services/trading/strategies/stair_climber.py`
- `backend/app/services/trading/strategies/__init__.py`
- `backend/app/services/trading/engine.py` — STRATEGY_REGISTRY
- `backend/app/api/v1/trading.py` — описание стратегии

**Что:**
- Новая стратегия для TradingEngine
- Логика: N последовательных higher highs + higher lows + растущий объём
- Вход на откате к EMA(9)
- Выход по SL/TP или сигналу разворота

---

## 🟢 Фаза 8 — Real mode (завершение)

**Файлы:**
- `backend/app/services/trading/engine.py` — `run_real()`
- `backend/app/services/trading/exchange/binance.py` — create_order, get_balance
- `backend/app/services/trading/exchange/mexc.py` — если нужно
- `backend/app/services/trading/scheduler.py` — проверка ключей
- `app/lib/features/trading/presentation/trading_signals_tab.dart` — real кнопка

**Что:**
- `run_real()` создаёт реальный ордер через API ключ
- Проверка баланса, SL ордер сразу при входе
- Лимит убытка (max_loss = balance × 0.3)
- Подтверждение через Telegram

---

## 🚫 НЕ меняем

- Существующие стратегии в `strategies/` (hammer, supertrend, rsi и т.д.) — не трогаем
- OB Engine (`orderbook/`) — не рефакторим
- Визард OB (`orderbook_wizard_page.dart`) — не меняем
- Страницу деталей OB-запуска
- Тему, хедер, основную навигацию
- Login / Auth / Users
- Hermes pipeline и агентов

---

## ⏱ Оценка

| # | Фаза | Время |
|---|------|-------|
| 🔴 1 | Telegram парсеры + модель сигналов | ~35 мин |
| 🔴 2 | Маппер сигналов → стратегии + endpoint | ~30 мин |
| 🟡 3 | Сигналы на странице трейдинга (таб) | ~45 мин |
| 🟡 4 | Telegram уведомления | ~20 мин |
| 🟡 5 | API ключи (бэкенд) | ~40 мин |
| 🟢 6 | API ключи (фронтенд) | ~40 мин |
| 🟢 7 | Stair Climber Strategy | ~45 мин |
| 🟢 8 | Real mode | ~30 мин |
| | **Итого:** | **~4.5 ч** |

---

## 📊 Поток данных (полный цикл)

```
@brushscreener / @stairscreener
         ↓
[cronjob] TelegramParser.fetch() → extract() → save to DB (trading_signals)
         ↓
[cronjob/after] SignalMapper.classify() → update signal in DB (mapped_strategy, mapped_params)
         ↓
┌─────────── Событие: новый сигнал ───────────┐
│                                              │
├─→ API: GET /trading/signals ← TradingPage    │
│   (фронтенд показывает карточки сигналов)    │
│                                              │
├─→ NotificationBot → Telegram уведомление     │
│                                              │
└──────────────────────────────────────────────┘
         ↓
Пользователь нажимает «🚀 Запустить virtual»
         ↓
Маппер определяет endpoint и параметры:
  - Ёршик → POST /orderbook/start {ers_scalping params}
  - Лесенка → POST /trading/runs {stair_climber params}
         ↓
Scheduler → Engine (virtual mode)
         ↓
Результаты → TradingPage (активные запуски)
```

---

Утверждаешь план v2? 🔥
