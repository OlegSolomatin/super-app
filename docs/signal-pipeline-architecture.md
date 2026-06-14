# Сигналы: архитектура пайплайна

> Шпаргалка по всему циклу обработки сигналов — от Telegram-канала до сайта и Telegram-бота.

---

## 🧭 Общая схема

```
                    ВНЕШНИЙ МИР
┌──────────────────────────────────────────────────────┐
│  Telegram Каналы                                      │
│  ┌──────────────┐  ┌──────────────┐                  │
│  │ brushscreener│  │stairscreener │                  │
│  └──────┬───────┘  └──────┬───────┘                  │
│         │                 │ (HTML страницы)           │
└─────────┼─────────────────┼──────────────────────────┘
          │                 │
          ▼                 ▼
┌──────────────────────────────────────────────────────┐
│ 1. ПАРСЕР  parse_telegram_signals.py --daemon       │
│                                                      │
│  • Каждые 5с парсит HTML каналов (httpx)            │
│  • Извлекает: pair, price_range, vol, slope, ratio  │
│  • Дедaп по data-post ID (Redis last_id:{channel})  │
│  • Сохраняет в PostgreSQL (TradingSignal)            │
│  • Публикует в Redis (channel:signal:new)            │
│  ⏱ ~2-5с на весь цикл                              │
└──────────────────────┬───────────────────────────────┘
                       │ Redis PUBLISH
                       ▼
┌──────────────────────────────────────────────────────┐
│ 2. МЭППЕР  map_signals_daemon.py  (LLM)             │
│                                                      │
│  • Слушает Redis (channel:signal:new)                │
│  • Берёт сигнал + его канал                          │
│  • По каналу определяет 2 варианта стратегий:        │
│    - brushscreener → ers_scalping / imbalance_scalping│
│    - stairscreener → stair_climber / ers_scalping    │
│  • Отправляет запрос в DeepSeek Flash (промпт~300тк) │
│  • LLM выбирает стратегию + params + reasoning       │
│  • Параллельно проверяет пару на биржах пользователя │
│    (check_available_exchanges: Bybit, Binance, etc)  │
│  • Сохраняет mapped поля в PostgreSQL                │
│  • Обновляет Redis:                                  │
│    - PUBLISH channel:signal:mapped (для нотифаера)   │
│    - обновляет signals:latest (для сайта)            │
│  ⏱ ~1-3с на сигнал (из них LLM ~1с)                │
└──────────────────────┬───────────────────────────────┘
                       │  Redis PUBLISH
          ┌────────────┴────────────┐
          ▼                         ▼
┌──────────────────────┐  ┌───────────────────────────┐
│ 3. НОТИФАЕР          │  │ 4. САЙТ / API             │
│ notification_bot.py  │  │                           │
│                      │  │  • SSE поток:             │
│  • Слушает Redis:     │  │    /trading/signals/live  │
│    - signal:new      │  │    /stream (real-time)    │
│    - signal:mapped   │  │                           │
│                      │  │  • REST:                  │
│  • signal:new →      │  │    GET /trading/signals   │
│    сырое уведомление  │  │    (из БД, с mapped)     │
│    (без классиф.)    │  │                           │
│                      │  │  • Redis signals:latest   │
│  • signal:mapped →   │  │    (50 посл. сигналов)   │
│    полное с ✅/❌    │  │                           │
│                      │  │  ⏱ ~0.05с                │
│  ⏱ ~0.5с (Telegram) │  │                           │
└──────────────────────┘  └───────────────────────────┘
```

---

## 📦 Сервисы и технологии

| Сервис | Роль | Используется в |
|--------|------|----------------|
| **Telegram (HTML)** | Источник сигналов | Парсер (httpx requests) |
| **PostgreSQL** | Хранение сигналов, mapped полей | Парсер (save), Мэппер (update), API (list) |
| **Redis** | Быстрая очередь, pub/sub, кеш | Все 4 этапа |
| **DeepSeek Flash** | LLM классификация сигналов | Мэппер (POST api.deepseek.com) |
| **Binance/Bybit API** | Проверка наличия пары | Мэппер (get_ticker) |
| **FastAPI** | Веб-сервер, REST + SSE | Сайт |
| **Telegram Bot API** | Отправка уведомлений | Нотифаер |

---

## ⏱ Хронометраж (сигнал → доставка)

```
Сигнал появился
  │
  ├── Парсер обнаружил:    0-5с (poll 5s)
  │   └── Сохранил + publish: +2-3с
  │
  ├── Мэппер получил:      ~0.01с (Redis pubsub)
  │   ├── LLM классификация: +1-2с
  │   └── Проверка бирж:    +0.3-1с (параллельно)
  │
  ├── Нотифаер получил:    ~0.01с (Redis pubsub)
  │   └── Отправил в TG:    +0.5с
  │
  └── Сайт обновился:      ~0.05с (SSE/Redis)
```

**Итого: ~3.5 — 10 секунд** от появления сигнала до уведомления.

---

## 🧠 Логика LLM классификации

### Канал → 2 варианта

```
brushscreener:
  ┌─ A) ers_scalping (ob)        — равные top/bot, малый range
  └─ B) imbalance_scalping (ob)  — одна сторона >1.5x

stairscreener:
  ┌─ A) stair_climber (trading)  — крутой slope, тренд
  └─ B) ers_scalping (ob)        — консолидация, малый range
```

### Что получает LLM

```
Сигнал: stairscreener, PEPEUSDT
range: 1.8%  vol60m: $890K  vol10m: $340K  slope: 6.2

Вариант A — stair_climber
  Параметры: timeframe: 1m/3m/5m/15m, stoploss: 1.0~5.0%, ...
Вариант B — ers_scalping
  Параметры: stoploss: -0.5~-3.0%, trailing_stop: 0.1~1.0, ...
```

### Что отвечает LLM

```json
{
  "variant": "A",
  "strategy": "stair_climber",
  "confidence": 0.85,
  "params": {"stoploss": 2.0, "takeprofit": 5.0, "timeframe": "3m"},
  "reasoning": "slope 6.2 + vol10m 38% от vol60m — сильное трендовое движение"
}
```

---

## 📊 Структура данных

### В PostgreSQL (trading_signals)

| Поле | Тип | Откуда |
|------|-----|--------|
| id | int | auto |
| channel | str | парсер |
| pair | str | парсер |
| price_range, vol_60m, vol_10m | float? | парсер |
| slope, top_ratio, bot_ratio | float? | парсер |
| mapped_engine, mapped_strategy | str? | **LLM** |
| mapped_params | JSONB? | **LLM** |
| mapped_confidence | float? | **LLM** |
| mapped_reasoning | str? | **LLM** |
| mapped_available_exchanges | JSONB? | check_exchanges |
| mapped_exchange_fallback | str? | check_cross_exchange |

### В Redis

| Ключ | Тип | Назначение |
|------|-----|------------|
| `signal:channel:last_id:{ch}` | string | Дедaп (последний ID) |
| `signal:raw:{ch}:{pair}` | string | Кеш сигнала (7 дней TTL) |
| `signals:latest` | list (50) | Лента для сайта |
| Pub/Sub `channel:signal:new` | — | Уведомление мэппера + нотифаера |
| Pub/Sub `channel:signal:mapped` | — | Уведомление нотифаера + SSE |

---

## 🔧 Как перезапустить

```bash
# Все три демона
cd ~/workspace/super-app/backend
export PYTHONPATH=$PWD

python3 scripts/parse_telegram_signals.py --daemon    # парсер
python3 scripts/map_signals_daemon.py                 # мэппер
python3 app/services/signals/notification_bot.py      # нотифаер

# FastAPI (если нужно)
uvicorn app.main:app --host 0.0.0.0 --port 8000

# Миграции (если новые поля)
alembic upgrade head
```

---

## 🗂 Структура файлов

```
backend/
├── scripts/
│   ├── parse_telegram_signals.py   # Парсер (демон)
│   └── map_signals_daemon.py       # Мэппер (демон)
├── app/
│   ├── services/signals/
│   │   ├── signal_mapper.py        # LLM классификация + сохранение
│   │   ├── strategy_config.py      # Канал → 2 стратегии + params
│   │   ├── notification_bot.py     # Нотифаер (демон)
│   │   └── telegram_parser.py      # HTTP парсинг каналов
│   ├── models/
│   │   └── trading_signal.py       # Модель БД
│   ├── schemas/
│   │   └── trading_signal.py       # Pydantic схемы
│   └── api/v1/
│       └── trading_signals.py      # REST + SSE endpoints
```

---

> 📅 Создано: 14.06.2026  
> 📄 Связанный план: `docs/plans/signal-pipeline-v2.md`
