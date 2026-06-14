# 📋 План: Real Mode — торговля на реальный баланс

> **Цель:** Добавить режим реальной торговли (Real Mode) в Order Book систему. Стратегии, настройки, визард — без изменений. Меняется только источник баланса и исполнение сделок (реальные ордера на Binance/Bybit).

---

## Архитектура

```
Frontend                        Backend
┌──────────────┐               ┌──────────────────┐
│ Модалка:     │  POST /start  │ Scheduler         │
│ Virtual/Real │ ───────────►  │  ├─ mode=virtual→VirtualEngine
│              │               │  └─ mode=real   →RealEngine
│ Если Real:   │               │                       │
│ есть ключи?  │◄──── 200 ────│  ExchangeKeys DB ──────┤
│ ─► Визард    │               │  (Fernet шифрование)   │
│ ─► Запуск    │               │                       ▼
└──────────────┘               │  ccxt/exchange ──── ордер
                               │  get_balance()
                               │  create_order()
                               └──────────────────────────┘
```

---

## 🟢 Фаза 1 — Модель хранения API-ключей ✅ ГОТОВО

**Файлы:**
- ✅ `backend/app/models/exchange_key.py` — модель (расширена: label, passphrase, balance)
- ✅ `backend/app/core/encryption.py` — Fernet через `SECRET_KEY` (SHA256)
- ✅ Миграция `005_create_exchange_keys.py`
- ✅ Роутер зарегистрирован в `app/api/router.py`

**Фактически:** сделано лучше плана — с поддержкой нескольких бирж (binance, bybit), статусом, балансом.

---

## 🟢 Фаза 2 — API для управления ключами ✅ ГОТОВО

**Endpoints:**
| Endpoint | Статус |
|----------|--------|
| `GET    /exchange-keys` (список) | ✅ |
| `POST   /exchange-keys` (сохранить) | ✅ |
| `PUT    /exchange-keys/{id}` (обновить) | ✅ |
| `DELETE /exchange-keys/{id}` (удалить) | ✅ |
| `POST   /exchange-keys/{id}/check` (verify + balance) | ✅ |

**Файлы:**
- ✅ `backend/app/schemas/exchange_key.py`
- ✅ `backend/app/api/v1/exchange_keys.py`

---

## 🟡 Фаза 3 — RealEngine (частично)

**По плану:** отдельный класс `RealOrderBookEngine` + `RealWallets`.

**Фактически:**
| Компонент | Статус | Комментарий |
|-----------|--------|-------------|
| `RealOrderBookEngine` класс | ❌ НЕТ | Заменён на композицию через executor |
| `OrderBookEngine(executor=...)` | ✅ | Принимает executor для real ордеров |
| `ExchangeExecutor` | ✅ | `execution/router.py` — создаёт ccxt-клиент по trade_exchange |
| `PriceNormalizer` | ✅ | Скользящая цена, слайдж, fallback |
| `DataExchangeRouter` | ✅ | Связывает DataProvider и ExchangeExecutor |
| RealWallets | ❌ НЕТ | Баланс получается через executor напрямую |
| `engine._execute_*` для real | ✅ | `place_order`, `cancel_order` через executor |

**Вывод:** архитектура через композицию (executor) **гибче** планового наследования. Бэкенд может торговать в real mode. Но отдельного RealEngine класса нет.

---

## 🟡 Фаза 4 — Scheduler + API для mode=real (частично)

| Компонент | Статус |
|-----------|--------|
| `scheduler.start_orderbook_run()` с mode=real | ✅ Строка 724: создаёт `ExchangeExecutor` |
| `OrderBookConfig.mode` поле | ✅ `models.py:164` |
| `executor` передаётся в `OrderBookEngine` | ✅ |
| API `POST /orderbook/start` с mode | ✅ `schemas/trading.py` |
| **Проверка active real runs (для OB)** | ❌ НЕТ |
| **Cooldown между запусками (для OB)** | ❌ НЕТ |

---

## 🔴 Фаза 5 — Режим «Real Mode» на фронте ❌ НЕ СДЕЛАНО

| Компонент | Статус | Детали |
|-----------|--------|--------|
| Модалка выбора режима | ❌ **Заглушка «Скоро»** | `trading_page.dart:559` |
| Визард с mode=real | ❌ **НЕТ** | Нет индикатора биржевого баланса |
| Страница API-ключей | ⚠️ **Частично** | Виджет `ExchangeKeySection` есть, отдельной страницы нет |
| Предупреждение о real сделках | ❌ **НЕТ** | |

---

## 🔴 Фаза 6 — Безопасность (частично)

| Компонент | Статус |
|-----------|--------|
| Шифрование Fernet | ✅ **ГОТОВО** |
| `MAX_REAL_RUNS` (лимит 3) | ❌ **НЕТ** |
| `REAL_MODE_COOLDOWN` (60s) | ❌ **НЕТ** |
| Проверка active real (для Candle) | ⚠️ **Есть в `trading.py`** (не для OB) |
| Логирование real операций | ⚠️ **Частично** (есть базовые логи) |

---

## 🔴 Фаза 7 — UI бейдж Real ❌ НЕ СДЕЛАНО

| Компонент | Статус |
|-----------|--------|
| Бейдж Real/Virtual на карточке запуска | ❌ **НЕТ** |
| Жёлтый `warningCircle` для real mode | ❌ **НЕТ** |

---

## 🔴 Фаза 8 — Балансовый мониторинг ❌ НЕ СДЕЛАНО

| Компонент | Статус |
|-----------|--------|
| Эндпоинт `/real-balance` | ❌ **НЕТ** |
| Показ баланса USDT на странице трейдинга | ❌ **НЕТ** |

---

## 🚩 Вне плана: Candle Trading `run_real()` — ОПАСНО

**Файл:** `backend/app/services/trading/engine.py:284`

**Проблема:** `run_real()` вызывает `self._execute(candles, real_exchange=real_exchange)`, который **прогоняет всю историю свечей мгновенно**. Каждый вход и выход — **реальный market-ордер** на бирже. Без реального времени, без проскальзывания, без проверки баланса между сделками.

**Потенциальный ущерб:** десятки ордеров за секунду на реальном балансе.

**Решение:** не в этом плане. Нужен отдельный план для Candle Real Mode (по аналогии с `run_virtual_live` — с `asyncio.sleep` между свечами).

---

## 📊 Сводка

| Фаза | Описание | Статус |
|------|----------|--------|
| 🔴 1 | Модель API-ключей + шифрование | ✅ **ГОТОВО** |
| 🔴 2 | API endpoints для ключей | ✅ **ГОТОВО** |
| 🔴 3 | Real Engine (executor) | 🟡 **Частично** (через executor, без отдельного класса) |
| 🟡 4 | Scheduler + API для mode=real | 🟡 **Частично** (запуск есть, лимитов нет) |
| 🟢 5 | Фронт: выбор mode, страница ключей, визард | 🔴 **НЕ СДЕЛАНО** |
| 🔴 6 | Безопасность: лимиты, кулдаун | 🔴 **НЕ СДЕЛАНО** |
| 🟢 7 | UI бейдж Real/Virtual | 🔴 **НЕ СДЕЛАНО** |
| 🟢 8 | Балансовый мониторинг | 🔴 **НЕ СДЕЛАНО** |

**Итого:** бэкенд **может** запускать OB в real mode (фазы 1-4). Фронт **не даёт** этого сделать (фазы 5-8 не реализованы). Плюс опасный `run_real()` в Candle Trading вне плана.

---

## ⚠️ Риски

| Риск | Статус | Решение |
|------|--------|---------|
| Потеря средств из-за бага в engine | 🔴 **Не решено** | Ограничить real mode: макс. 3 запуска, % баланса |
| API-ключи с read-only правами | 🟡 Частично | Проверка при `/check` есть |
| Rate limits биржи | 🟡 Частично | Не реализовано |
| Проскальзывание market orders | ✅ **Решено** | PriceNormalizer + limit orders |
