# План: Фаза 8 — Real mode (реальная торговля через API бирж)

**Цель:** Запускать стратегии с реальными деньгами через API-ключи Binance/Bybit.

---

## 📊 Текущий статус

- ✅ `place_order()` и `get_balance()` — заглушки (возвращают REJECTED)
- ✅ `engine.run_real()` — тупо вызывает `_execute()` (как история)
- ✅ `scheduler._execute_run()` — проверяет `mode == "real"` → вызывает `run_real`
- ✅ API-ключи уже хранятся в БД (зашифрованы Fernet)
- ✅ `BalanceChecker` умеет проверять валидность ключа и баланс

---

## 🔴 Фаза 8.1 — Binance place_order + get_balance

**Файлы:** `backend/app/services/trading/exchange/binance.py`

Реализовать подписанные запросы к Binance API:
- `place_order()` → `POST /api/v3/order` (signed)
- `get_balance()` → `GET /api/v3/account` (signed)

Подпись: HMAC-SHA256 из `api_secret`, timestamp + recvWindow.

---

## 🟡 Фаза 8.2 — Scheduler: валидация и проверка ключей

**Файлы:** `backend/app/services/trading/scheduler.py`, `backend/app/services/trading/engine.py`

Перед real-запуском:
1. Достать API-ключ из БД (по `user_id` + `exchange`)
2. Проверить статус = `valid` (если invalid — отказ)
3. Проверить баланс ≥ `config.virtual_balance`
4. Проверить: нет других активных real-запусков (макс 1)
5. Если всё ок — создать BinanceExchange с ключами, запустить `run_real`

---

## 🔴 Фаза 8.3 — Engine.run_real() — реальная торговля

**Файлы:** `backend/app/services/trading/engine.py`

`run_real()` будет:
1. Использовать переданный `exchange` с API-ключами
2. Получить реальный баланс (`exchange.get_balance('USDT')`)
3. Анализировать свечи как обычно
4. При сигнале на вход:
   - Рассчитать размер позиции (не больше баланса × 0.95)
   - `exchange.place_order(pair, 'buy', quantity, 'market')`
   - **Сразу** выставить SL-лимитный ордер
   - Сохранить `order_id` в открытую сделку
5. При сигнале на выход или TP/SL:
   - `exchange.place_order(pair, 'sell', quantity, 'market')`
6. Логировать все ордеры

**Безопасность:**
- Max loss: `balance × 0.3` за запуск
- Max 1 real запуск одновременно
- SL ставится сразу при входе (лимитный ордер, не надеемся на мониторинг)
- Все ордеры логируются в `trading_trades`

---

## 🟡 Фаза 8.4 — Frontend: кнопка Real Mode

**Файлы:** `wizard_page.dart`, `trading_signals_tab.dart`, `trading_page.dart`

- В модалке выбора режима — **«Real ⚡»** (сейчас заглушка «⛔ Скоро»)
- В карточке сигнала — кнопка **«🚀 Real»**
- Real запуск:
  1. Модалка подтверждения: «Запустить {стратегия} на {пара} с реальным балансом ${N}?»
  2. Кнопка «Подтвердить» → POST /trading/signals/{id}/start?mode=real
  3. После запуска — SnackBar «Запущен real-режим для {пара}»

---

## 🔴 Фаза 8.5 — Dashboard: метка Real на запусках

**Файлы:** `active_run_card.dart`, `run_detail_page.dart`

- Real-запуски помечаются значком **⚡** и красной обводкой
- В деталях показан реальный PnL (не виртуальный)
- Кнопка **«Экстренный стоп»** — отменяет ордер, закрывает позицию market

---

## ⏱ Оценка времени

| Подфаза | Время |
|---------|-------|
| 8.1 Binance signed API | ~30 мин |
| 8.2 Scheduler validation | ~20 мин |
| 8.3 Engine.run_real() | ~45 мин |
| 8.4 Frontend buttons | ~20 мин |
| 8.5 Dashboard markers | ~15 мин |
| **Итого** | **~2 ч** |
