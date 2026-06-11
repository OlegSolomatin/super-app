# План: Интеграция Telegram-сигналов + API бирж + Real mode

> **Цель:** Связать скринеры @brushscreener и @stairscreener с платформой для автоматического запуска стратегий, добавить управление API ключами бирж и подготовить real mode.

**Архитектура:** Telegram cronjob → парсер → маппер стратегий → уведомление с кнопкой запуска → scheduler → engine (virtual → real). API ключи бирж хранятся в БД, проверяются баланс и статус.

---

| # | Приоритет | Фаза | Описание | Время |
|---|-----------|------|----------|-------|
| 1 | 🔴 | Telegram парсеры | Cronjob для @brushscreener и @stairscreener | ~30 мин |
| 2 | 🔴 | Маппер сигналов | Сигнал → стратегия + настройки | ~30 мин |
| 3 | 🟡 | Telegram уведомления | Форматированный пост + кнопка запуска | ~30 мин |
| 4 | 🟡 | API ключи (бэкенд) | Модель, CRUD, проверка баланса | ~40 мин |
| 5 | 🟢 | API ключи (фронтенд) | Страница настроек с полями + статусы | ~40 мин |
| 6 | 🟢 | Stair Climber Strategy | Новая стратегия для «лесенок» | ~45 мин |
| 7 | 🟢 | Real mode | Завершение real mode для бирж | ~30 мин |
| | | **Итого:** | | **~4 часа** |

---

## 🔴 Фаза 1 — Telegram парсеры

**Файлы:**
- `backend/app/services/signals/telegram_parser.py` — новый модуль
- `backend/scripts/parse_telegram_signals.py` — cronjob-скрипт
- `backend/app/services/signals/__init__.py` — новый пакет

**Что:**
- Парсит `t.me/s/brushscreener` и `t.me/s/stairscreener` каждые 2-3 минуты через cronjob
- Извлекает: биржа, пара, price_range, vol_60m, vol_10m, slope (stairs), top_bot_ratio (brush)
- Хранит последние N сигналов в локальном JSON/памяти
- Дедупликация по паре + времени (не отправлять повторно одно и то же)

**Действия:**
1. Создать пакет `backend/app/services/signals/`
2. Написать класс `TelegramParser` с методами:
   - `fetch_channel(channel_url)` — забирает HTML, извлекает сообщения
   - `parse_brush_signal(text)` — парсит ёршик (биржу, пару, range, vol, top/bot)
   - `parse_stair_signal(text)` — парсит лесенку (биржу, пару, range, vol, slope)
3. Создать `scripts/parse_telegram_signals.py` — скрипт для cronjob
4. Добавить cronjob через Hermes: `cronjob(action='create', schedule='every 3m', script='parse_telegram_signals.py')`

**НЕ меняем:**
- `backend/app/services/trading/` — не трогаем
- Существующие engine / scheduler — только используем их API

---

## 🔴 Фаза 2 — Маппер сигналов → стратегии

**Файлы:**
- `backend/app/services/signals/signal_mapper.py` — новый модуль
- `backend/app/services/trading/strategies/__init__.py` — добавить импорт stair_climber

**Что:**
- Логика: по данным сигнала определяет, какую стратегию запустить и с какими настройками

**Маппинг:**
| Тип | Условие | Стратегия | Параметры |
|-----|---------|-----------|-----------|
| Ёршик | Top/Bot ~равны, Range < 3% | `ers_scalping` (OB) | TF=1m, mc=0.05, SL=1.5%, TP=3% |
| Лесенка | Slope > 5, Vol10m растёт | `stair_climber` (новая) | TF=3m, mc=0.03, SL=2%, TP=5% |
| Дисбаланс | Top/Bot ≠ 2×, Range > 3% | `imbalance_scalping` (OB) | TF=1m, aggressive |
| Всплеск объёма | Vol10m > Vol60m × 0.3 | `order_flow_momentum` (OB) | TF=1m, fast exit |

**Действия:**
1. Написать `SignalMapper.classify(signal)` → `{strategy, params, pair, exchange}`
2. Метод `generate_recommendation(signal)` → человекочитаемая рекомендация

**НЕ меняем:**
- Стратегии в `strategies/` — только добавляем новую (stair_climber) в Фазе 6

---

## 🟡 Фаза 3 — Telegram уведомления + кнопки запуска

**Файлы:**
- `backend/app/services/signals/notification_bot.py` — новый модуль
- `backend/app/services/signals/signal_mapper.py` — добавить метод форматирования

**Что:**
- При новом сигнале отправляет уведомление в Telegram Олегу
- Формат с эмодзи, метриками, рекомендованной стратегией и настройками
- Кнопка быстрого запуска (через Telegram bot command)

**Формат уведомления:**
```
🔔 Сигнал: WOJAK/USDT
📊 Тип: Ёршик (Top/Bot: 0.09/0.09)
🏛 Биржа: Mexc Futures
📈 Range: 2.0% | Vol: 10 227$
———————————————
🎯 Стратегия: ers_scalping
⚙️ Параметры:
  • TF: 1m | mc: 0.05
  • SL: 1.5% | TP: 3%
  • max_trade: $2
🚀 /start_signal WOJAK USDT ers_scalping
```

**Действия:**
1. Написать `NotificationBot` — отправка через send_message
2. Форматирование рекомендации в красивый пост
3. Обработка команды `/start_signal <pair> <strategy>` — вызов API для запуска virtual mode

**НЕ меняем:**
- Существующий Telegram Mini App
- Hermes-уведомления (не ломать существующие)

---

## 🟡 Фаза 4 — API ключи бирж (бэкенд)

**Файлы:**
- `backend/app/models/exchange_key.py` — новая модель SQLAlchemy
- `backend/app/schemas/exchange_key.py` — новый Pydantic schema
- `backend/app/api/v1/exchange_keys.py` — новый роутер
- `backend/app/api/router.py` — добавить импорт роутера
- `backend/app/services/exchange/balance_checker.py` — новый сервис

**Что:**
- Модель: `ExchangeKey {id, user_id, exchange_name, api_key, api_secret, is_active, created_at}`
- API ключи хранятся зашифрованными (Fernet или AES)
- Эндпоинты: GET/POST/PUT/DELETE /api/v1/exchange-keys
- Проверка ключа: при сохранении делает тестовый запрос к бирже (fetch_balance)
- Статус: `valid` / `invalid` / `insufficient_permissions`

**Модель ExchangeKey:**
```python
class ExchangeKey(Base):
    __tablename__ = "exchange_keys"
    id: int = Column(Integer, primary_key=True)
    user_id: UUID = Column(ForeignKey("users.id"), nullable=False)
    exchange: str = Column(String(50), nullable=False)  # binance, mexc, bybit
    api_key_encrypted: str = Column(String(512), nullable=False)
    api_secret_encrypted: str = Column(String(1024), nullable=False)
    is_active: bool = Column(Boolean, default=True)
    status: str = Column(String(20), default="untested")  # untested, valid, invalid
    balance: Optional[float] = Column(Float, default=None)
    created_at: datetime = Column(DateTime, default=func.now())
    updated_at: datetime = Column(DateTime, default=func.now(), onupdate=func.now())
```

**Эндпоинты:**
- `POST /api/v1/exchange-keys` — добавить ключ (шифрует, тестирует, возвращает статус + баланс)
- `GET /api/v1/exchange-keys` — список ключей пользователя (без секретов!)
- `PUT /api/v1/exchange-keys/{id}` — обновить ключ
- `DELETE /api/v1/exchange-keys/{id}` — удалить ключ
- `POST /api/v1/exchange-keys/{id}/check` — принудительная проверка + обновление баланса

**Balance Checker:**
```python
class BalanceChecker:
    async def check_key(self, exchange: str, api_key: str, api_secret: str) -> dict:
        # Создаёт подключение к бирже
        # Делает fetch_balance()
        # Возвращает {status, balance, error}
```

**НЕ меняем:**
- Существующие endpoints auth/trading/orderbook
- `backend/app/services/trading/` — не трогаем

---

## 🟢 Фаза 5 — API ключи (фронтенд)

**Файлы:**
- `app/lib/features/settings/presentation/exchange_keys_page.dart` — новая страница
- `app/lib/features/settings/data/exchange_key_repository.dart` — API-клиент
- `app/lib/features/settings/presentation/settings_page.dart` — добавить пункт меню
- `app/lib/router/router_config.dart` — добавить маршрут
- `app/lib/features/settings/presentation/providers/exchange_keys_provider.dart` — state management

**Что:**
- Страница в настройках: «API ключи бирж»
- Список добавленных ключей с статусом (🟢 valid, 🔴 invalid, ⚪ untested)
- Форма добавления: выбор биржи (Binance, Mexc, Bybit), поля API Key + Secret
- После добавления — тестовый запрос, показ баланса
- Возможность удалить / обновить ключ

**UI:**
```
Настройки → API ключи

┌────────────────────────────────┐
│ Binance        🟢 $1,245.30    │
│ API Key: ***...a1b2           │
│ Действия: [Проверить] [Удалить] │
├────────────────────────────────┤
│ Mexc           🔴 Недействит.  │
│ Действия: [Проверить] [Удалить] │
├────────────────────────────────┤
│ [+ Добавить биржу]             │
└────────────────────────────────┘
```

**Действия:**
1. Создать `ExchangeKeyRepository` — REST-запросы к `/api/v1/exchange-keys`
2. Создать `ExchangeKeysProvider` — Riverpod state
3. Создать `ExchangeKeysPage` — список + форма добавления
4. Обновить роутер и меню настроек

**НЕ меняем:**
- TradingPage, WizardPage, RunDetailPage
- Тему, хедер, навигацию (не добавлять лишние иконки в хедер)

---

## 🟢 Фаза 6 — Stair Climber Strategy

**Файлы:**
- `backend/app/services/trading/strategies/stair_climber.py` — новая стратегия
- `backend/app/services/trading/strategies/__init__.py` — добавить импорт
- `backend/app/services/trading/engine.py` — добавить в STRATEGY_REGISTRY
- `backend/app/api/v1/trading.py` — добавить описание стратегии

**Что:**
- Новая стратегия для паттерна «лесенка»: цена идёт ступеньками с нарастающим объёмом
- Работает на малых ТФ (1m-3m), ищет последовательные импульсы с откатами

**Логика:**
```python
def analyze(self, candles):
    # 1. Найти N последовательных свечей с higher highs + higher lows
    # 2. Проверить объём: растёт с каждой ступенькой
    # 3. Рассчитать slope: (price_N - price_0) / N / volatility
    # 4. Если slope > threshold и объём растёт → сигнал BUY
    # 5. Вход на откате к EMA(9) после подтверждения
    # 6. Выход: TP по следующей ступеньке или SL по предыдущей
```

**Параметры:**
- `min_steps: int = 3` — минимум ступенек для подтверждения
- `slope_threshold: float = 3.0` — минимальный наклон
- `volume_growth: float = 1.2` — объём каждой ступеньки > предыдущей × growth
- `pullback_ema: int = 9` — вход на откате к этой EMA

**Действия:**
1. Написать `StairClimberStrategy(AbstractStrategy)`
2. Добавить `_detect_stairs(candles)` — находит лесенки
3. Добавить `_compute_slope(prices)` — вычисляет наклон
4. Добавить стратегию в хардкод список API
5. Покрыть базовыми тестами

**НЕ меняем:**
- Существующие стратегии (supertrend, hammer, и т.д.)
- OrderBookEngine

---

## 🟢 Фаза 7 — Real mode

**Файлы:**
- `backend/app/services/trading/engine.py` — доработать `run_real()`
- `backend/app/services/trading/exchange/binance.py` — добавить create_order, get_balance
- `backend/app/services/signals/notification_bot.py` — real mode уведомления
- `backend/app/services/trading/scheduler.py` — проверка ключей перед real mode

**Что:**
- `run_real()` создаёт реальный ордер на бирже через API ключ
- Проверка баланса перед открытием сделки
- Мониторинг open orders
- Автоматическое выставление SL/TP ордерами
- Логирование всех ордеров

**Валидация перед real mode:**
```python
async def _validate_real_mode(config, user_id):
    # 1. Есть ли API ключ для этой биржи
    # 2. Статус ключа = valid
    # 3. Баланс >= config.virtual_balance
    # 4. Не превышен лимит одновременных real-запусков
    # 5. Подтверждение пользователя (2-step)
```

**Безопасность:**
- Каждый real-ордер подтверждается через Telegram (кнопка)
- Stop-loss ставится сразу при входе
- Лимит убытка на запуск (max_loss = balance × 0.5)
- Только для верифицированных пользователей

**НЕ меняем:**
- Virtual mode (он уже работает, не сломать)
- OrderBookEngine (OB-стратегии пока только virtual)

---

## 🚫 НЕ меняем (полный список)

- `backend/app/services/trading/strategies/supertrend.py` — откатили, не трогаем
- `backend/app/services/trading/strategies/hammer.py` — работает
- `backend/app/services/trading/strategies/*.py` — существующие стратегии
- `backend/app/services/trading/orderbook/` — OB-движок
- `app/lib/features/trading/presentation/orderbook_wizard_page.dart` — визард не меняем
- `app/lib/features/trading/presentation/orderbook_run_detail_page.dart` — детали не меняем
- `app/lib/core/theme.dart` — тема
- `app/lib/router/router_config.dart` — только добавляем маршрут, не меняем существующие
- Hermes pipeline, agent-config, SOUL-файлы

---

## 📊 Схема потоков данных

```
┌──────────────┐     ┌──────────────────┐     ┌───────────────┐
│ @brushscreener│────→│ TelegramParser    │────→│ SignalMapper   │
│ @stairscreener│     │ (cronjob/3мин)    │     │ classify()     │
└──────────────┘     └──────────────────┘     └───────┬───────┘
                                                       │
                                                       ▼
┌──────────────────┐     ┌──────────────────┐     ┌───────────────┐
│ Telegram Bot     │←────│ NotificationBot  │←────│ Recommendation│
│ Уведомление      │     │ send_message()   │     │ + params      │
│ Кнопка "Запуск"  │     └──────────────────┘     └───────────────┘
└──────┬───────────┘
       │ /start_signal WOJAK ers_scalping
       ▼
┌─────────────────────────────────────────────────────┐
│ POST /api/v1/trading/runs  или  POST /orderbook/start│
│ Scheduler → Engine (virtual → real)                  │
└─────────────────────────────────────────────────────┘
```

---

## 💾 Хранение данных

```
Таблицы БД:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
exchange_keys   — API ключи бирж
  id | user_id | exchange | api_key_enc | api_secret_enc
  is_active | status | balance | created_at

signal_cache    — кэш последних сигналов (опционально)
  id | channel | pair | exchange | signal_type
  price_range | vol_60m | vol_10m | slope | top_bot
  mapped_strategy | created_at
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Существующие (не трогаем):
  users | trading_runs | trading_configs | trading_results
  trading_trades | orderbook_runs | sessions
```

---

Утверждаешь план? Если да — начинаю с Фазы 1. 🔥
