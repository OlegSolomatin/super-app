# PLAN: A/B Comparison — Order Book Strategy Battle

## 🎯 Идея

Запустить 2+ Order Book стратегии на **одной и той же паре** одновременно и сравнить их PnL, win rate, drawdown в реальном времени.

## 🔄 Flow

```
[TradingPage]
  ↓ нажал "A/B Battle" (новая кнопка)
[Modal: выбери стратегии]
  ├─ ☑ Imbalance Scalping
  ├─ ☑ Spread Capture
  └─ ☑ Order Flow Momentum
  ↓
[Modal: общие настройки]
  ├─ Пара (одна!)
  ├─ Баланс (делится между стратегиями)
  ├─ Stop Loss / Trailing / Max Hold
  └─ Precision / Protections
  ↓
🚀 Start Battle → POST /api/v1/orderbook/battle
```

## 🏗️ Архитектура

```
┌───────────────────────────────────────────────────┐
│                TradingPage                         │
│  [Запущенные] [История] [📗 OB] [⚔️ Battle]       │
│                                                     │
│  ┌──────── BATTLE ACTIVE ──────────────────┐       │
│  │ BTCUSDT · 3 engines running              │       │
│  │                                           │       │
│  │ ┌──────────┬──────────┬──────────┐       │       │
│  │ │Imbalance │  Spread  │  Flow    │       │       │
│  │ │ PnL:+1.2%│ PnL:-0.3%│ PnL:+0.8%│       │       │
│  │ │Trades: 8 │Trades: 5 │Trades:12 │       │       │
│  │ │Win: 62%  │Win: 40%  │Win: 58%  │       │       │
│  │ │🔴🔴🟢🟢│🔴🟢🟢🔴│🟢🟢🔴🟢│       │       │
│  │ └──────────┴──────────┴──────────┘       │       │
│  │    [Остановить всё]                       │       │
│  └───────────────────────────────────────────┘       │
└─────────────────────────────────────────────────────┘
```

## 📋 Фазы реализации

### Фаза B1 — Backend: Battle Engine

| # | Задача | Файлы | Оценка |
|---|--------|-------|--------|
| B1.1 | Создать `OrderBookBattleEngine` — запускает N engine на одной паре, общий баланс | `backend/app/services/trading/orderbook/engine.py` (новый класс) | 1ч |
| B1.2 | `BattleConfig` — список стратегий, общий pair/balance/stoploss | `backend/app/services/trading/orderbook/models.py` | 15м |
| B1.3 | API эндпоинт `POST /orderbook/battle` — старт, `GET /orderbook/battle/{id}` — статус | `backend/app/api/v1/orderbook.py` | 30м |
| B1.4 | API `POST /orderbook/battle/{id}/stop` — остановить все | `backend/app/api/v1/orderbook.py` | 15м |
| B1.5 | Модель `OrderBookBattleRun` в БД (или мета-запись) | `backend/app/models/trading.py` | 30м |
| B1.6 | Сохранение результатов battle (сводка по каждой стратегии) | `backend/app/services/trading/scheduler.py` | 30м |

### Фаза B2 — Frontend: UI сравнения

| # | Задача | Файлы | Оценка |
|---|--------|-------|--------|
| B2.1 | Кнопка "⚔️ A/B Battle" на TradingPage | `trading_page.dart` | 15м |
| B2.2 | Модалка выбора стратегий (чеки) + общие настройки | Новый `ab_battle_wizard.dart` | 1ч |
| B2.3 | Карточка активного battle на TradingPage (live-таблица) | `trading_page.dart` | 45м |
| B2.4 | История battle (завершённые) | `trading_page.dart` | 20м |
| B2.5 | Сборка v76 | — | 5м |

### Фаза B3 — Детализация (опционально)

| # | Задача | Оценка |
|---|--------|--------|
| B3.1 | График PnL каждой стратегии (fl_chart) | 1ч |
| B3.2 | Экспорт результатов в CSV | 30м |
| B3.3 | Telegram-уведомление о завершении battle | 30м |

## 🧬 Data Flow

```
POST /api/v1/orderbook/battle
{
  "pair": "BTCUSDT",
  "initial_balance": 3000,  // делим на 3 стратегии
  "strategies": [
    {"name": "imbalance_scalping", "params": {...}},
    {"name": "spread_capture", "params": {...}},
    {"name": "order_flow_momentum", "params": {...}}
  ],
  "common": {
    "stoploss": -1.0,
    "trailing_stop": 0.3,
    "max_hold_seconds": 120
  }
}
```

Battle Engine создаёт 3 отдельных `OrderBookEngine` (как сейчас работает), но с **общим WS-стримом** (один fetcher на всех, чтобы не плодить соединения). Каждый engine получает свой срез баланса и торгует независимо.

Результаты агрегируются в `OrderBookBattleRecord`:
```json
{
  "id": 42,
  "pair": "BTCUSDT",
  "started_at": "...",
  "finished_at": "...",
  "strategies": [
    {"name": "imbalance_scalping", "pnl": 1.2, "trades": 8, "win_rate": 62.5},
    {"name": "spread_capture", "pnl": -0.3, "trades": 5, "win_rate": 40.0},
    {"name": "order_flow_momentum", "pnl": 0.8, "trades": 12, "win_rate": 58.3}
  ]
}
```

## 🔗 Связи

| Компонент | Откуда вызывается | Куда идёт |
|-----------|-------------------|-----------|
| `OrderBookBattleEngine` | `scheduler.start_battle()` | Создаёт N `OrderBookEngine` |
| `POST /orderbook/battle` | API router → scheduler | Создаёт BattleRun в БД |
| `GET /orderbook/battle/{id}` | API router → engine.status | Возвращает агрегированные метрики |
| `POST /orderbook/battle/{id}/stop` | API router → engine.stop() | Останавливает все engine |
| `BattleCard` (Flutter) | Polling каждые 2с → GET | Отображает live-таблицу |

## ⏱️ Итого

| Фаза | Время |
|------|-------|
| B1 — Backend | ~3ч |
| B2 — Frontend | ~2.5ч |
| B3 — Детали | ~2ч |
| **Всего** | **~7.5ч** |

## ❓ Открытые вопросы

1. Баланс: делить поровну или каждый engine получает полный баланс?
   - **Ответ:** Делим поровну (3000 → 1000 на каждого)
2. WS: один fetcher на всех или каждому свой?
   - **Ответ:** Один fetcher, engine подписываются на общий `on_snapshot`
3. Нужна ли отдельная таблица в БД или использовать существующую?
   - **Ответ:** Новая модель `OrderBookBattleRun` + `OrderBookBattleStrategy` (child)
