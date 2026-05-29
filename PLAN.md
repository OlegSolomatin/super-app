# Super-App — План реализации

**Стек:** FastAPI (Python) + Flutter (Dart) + PostgreSQL + Redis + MinIO
**Платформы:** iOS + Android + Desktop (один код)

---

## 📋 Содержание

| Файл | О чём |
|------|-------|
| [`ARCHITECTURE.md`](ARCHITECTURE.md) | Архитектура системы, слои, технологический стек |
| [`STRUCTURE.md`](STRUCTURE.md) | Полная структура папок проекта |
| [`DB.md`](DB.md) | Схема базы данных (11 таблиц) |
| [`API.md`](API.md) | Полный список API эндпоинтов |
| [`CODESTYLE.md`](CODESTYLE.md) | Правила написания кода (Python + Dart) |
| `PLAN.md` | **Этот файл** — дорожная карта реализации |

---

## 🗺️ Дорожная карта (10 фаз)

| Фаза | Название | Время | Зависит от |
|------|----------|-------|-----------|
| 1 | Backend scaffold (FastAPI + БД) | 2-3ч | — |
| 2 | Модели + миграции | 2-3ч | Фаза 1 |
| 3 | Auth (JWT) | 2ч | Фаза 2 |
| 4 | Flutter scaffold + auth | 3-4ч | Фаза 3 |
| 5 | Посты (социальная сеть) | 4-5ч | Фаза 4 |
| 6 | Тренировки | 3-4ч | Фаза 4 |
| 7 | Музыкальный плеер | 4-5ч | Фаза 4 |
| 8 | Видеоплеер | 3-4ч | Фаза 4 |
| 9 | Карты / GPS трекинг | 4-5ч | Фаза 4 |
| 10 | Сборка + деплой | 2-3ч | Фазы 5-9 |
| **11** | **⚙️ Agent Monitoring Dashboard** | **3-4ч** | **Фаза 4** |

**Итого:** ~33-39 часов чистого времени.

---

## 🎯 Приоритет реализации

```
Фаза 1 ─→ Фаза 2 ─→ Фаза 3 ─→ Фаза 4 ─→ Фаза 5
                                            │
                              Фаза 6 ───────┤
                              Фаза 7 ───────┤
                              Фаза 8 ───────┤
                              Фаза 9 ───────┤
                              Фаза 11 ──────┤
                                            │
                                            ▼
                                        Фаза 10
```

**MVP** (минимально жизнеспособный продукт): Фазы 1-4 + одна из Фаз 5-9.
**Admin MVP**: Фазы 1-4 + Фаза 11 (запуск без модулей контента).

---

## 🛠 Агенты для выполнения

| Задача | Агент | Команда |
|--------|-------|---------|
| Backend (Python/FastAPI) | `backend-coder` | `backend-coder chat -q "..."` |
| Flutter клиент | `flutter-coder` | `flutter-coder chat -q "..."` |
| Инфраструктура | `devops` | `devops chat -q "..."` |

---

## ⚙️ Фаза 11: Agent Monitoring Dashboard

**Цель:** Админ-панель мониторинга агентов — плитка на главной → страница со списком всех агентов, их статусами и расходом токенов.

### 📊 Данные для отображения

| Поле | Источник | Описание |
|------|----------|----------|
| Имя агента | `agents.yaml` → `agents.<name>` | Ключ в реестре |
| Роль | `agents.yaml` → `agents.<name>.role` | Job description |
| Позиция | `agents.yaml` → `agents.<name>.position` | Номер в пайплайне |
| Модель | `agents.yaml` → `agents.<name>.model` + `model_context` | Текущая модель |
| Провайдер | `agents.yaml` → `agents.<name>.provider` | deepseek / openrouter |
| Этап | `agents.yaml` → `agents.<name>.pipeline_stage` | input/planning/execution/review/output |
| Статус | Процесс (pid) OR статус-файл | `idle` / `working` |
| Текущая задача | `knowledge.yaml` → `session.task` ИЛИ logs | Краткое описание |
| Токены (вход) | Hermes сессии / cost-tracker лог | Input tokens за сессию |
| Токены (выход) | Hermes сессии / cost-tracker лог | Output tokens за сессию |
| Стоимость $ | cost-tracker / API лог | Приблизительная стоимость |

### 🧩 Что нужно сделать

**Backend (`backend-coder`):**

1. **Скрипт-сборщик `scripts/collect_agent_stats.py`**
   - Парсит `agents.yaml` → список агентов с ролями/моделями
   - Проверяет запущенные процессы (`ps aux | grep <agent-profile>`) → статус `working`/`idle`
   - Парсит последние логи из `~/agent-control-room/logs/` → текущая задача
   - Собирает токены из Hermes сессий (`~/.hermes/sessions/` или профилей)
   - Пишет JSON в `~/agent-control-room/bus/agent_stats.json`

2. **Эндпоинт `GET /api/v1/admin/agents/status`** (admin-only)
   - Читает `agent_stats.json`
   - Возвращает массив: `[{name, role, model, provider, status, task, tokens_in, tokens_out, cost}]`

3. **WebSocket `ws://.../admin/agents/live`** (опционально)
   - Для real-time обновления статусов без polling

**Flutter (`flutter-coder`):**

4. **Админ-тил на HomePage** (виден только если `user.role == "admin"`)
   - Карточка с иконкой ⚙️ "Мониторинг агентов"
   - Показывает счётчик: "20 агентов, X активны"

5. **Страница `/admin/agents`**
   - Список всех агентов в пайплайн-порядке
   - Каждый элемент:
     - 🟢/🟡/🔴 индикатор статуса (idle/working/error)
     - Имя агента + роль
     - Модель и провайдер
     - 📊 Прогресс-бар токенов (использовано / лимит)
     - 💰 Стоимость за сессию
   - Если `status == "working"`:
     - Анимация пульсации/спиннера
     - Текст "Выполняет: <краткое описание задачи>"
   - Pull-to-refresh обновление
   - WebSocket live-обновление (если реализовано)

### 🔄 Интеграция с Agent Control Room

```
super-app backend
       │
       ▼
  GET /admin/agents/status
       │
       ▼
  collect_agent_stats.py
       │
       ├─── agents.yaml ───────→ имена, роли, модели
       ├─── knowledge.yaml ────→ текущий task
       ├─── ps aux ─────────────→ alive/dead
       └─── session logs ──────→ токены, статусы
       │
       ▼
  agent_stats.json ─────────────→ API → Flutter
```

### 🚀 Старт

```bash
# Фаза 1: Backend scaffold
```

## ⚙️ Фаза 12: Trading Wizard (9-шаговый мастер)

**Цель:** Плитка "Трейдинг" на главной → 9-шаговый мастер настройки бэктеста → запуск на исторических данных → позже live-торговля.

### 🧩 9 шагов Wizard-а

| Шаг | Название | Что настраивает |
|-----|----------|-----------------|
| 1 | **Биржа** | Выбор криптобиржи: Bybit / Binance / OKX / Mock |
| 2 | **Пара** | Выбор торговой пары: BTCUSDT, ETHUSDT, TONUSDT, SOLUSDT и т.д. |
| 3 | **Стратегия** | RSI, Hammer, Swing, Morning Star, Piercing Line, Две свечи |
| 4 | **Индикаторы** | Параметры стратегии: период RSI, MACD, EMA, пороги |
| 5 | **Риски** | Stop Loss %, Take Profit %, размер позиции % от баланса |
| 6 | **Таймфрейм** | 1m / 5m / 15m / 30m / 1h / 4h / 1d |
| 7 | **Период** | Дата начала и конца исторических данных |
| 8 | **Баланс** | Стартовый баланс $, комиссия % |
| 9 | **Запуск** | Сводка → кнопка "Запустить Backtest" → результаты |

### 🎯 Что нужно сделать

**Backend (`backend-coder`):**

1. **Перенести существующий backtest.py** из `~/workspace/crypto-ton/` в `backend/`
2. **Создать API эндпоинты:**
   - `GET /api/v1/trading/pairs` — список доступных пар
   - `GET /api/v1/trading/strategies` — список стратегий с параметрами
   - `GET /api/v1/trading/exchanges` — список бирж
   - `POST /api/v1/trading/backtest` — запуск бэктеста с конфигом
   - `GET /api/v1/trading/backtest/{id}/results` — результаты
   - `GET /api/v1/trading/backtest/{id}/history` — история сделок
3. **Хранить результаты** в PostgreSQL (таблица backtest_results)

**Flutter (`flutter-coder`):**

4. **Плитка "Трейдинг" на HomePage** — под админ-плиткой
5. **Страница `/trading/wizard`** — 9 шагов с Stepper/Slider
6. **Страница `/trading/results`** — результаты бэктеста (графики, метрики)
7. **Каждый шаг** — отдельный виджет с валидацией
8. **Навигация** — вперёд/назад с сохранением состояния

### 📊 Данные для бэктеста (из crypto-ton)

- База: `~/workspace/crypto-ton/data.db` (SQLite с историческими данными)
- Пары: BTCUSDT, ETHUSDT, TONUSDT, SOLUSDT и другие
- Таймфреймы: 1m, 5m, 15m, 30m, 1h, 4h, 1d
- Индикаторы: SMA, RSI, MACD, EMA, Bollinger, Volume Spike
- Стратегии: RSI (3 варианта), Hammer, Morning Star, Piercing Line, Swing

### 🚀 Этапы

1. **MVP**: Backend API + Wizard UI (9 шагов) + виртуальный бэктест
2. **V2**: Live-торговля через Bybit API с реальным балансом
3. **V3**: Мониторинг открытых позиций, PnL, авто-закрытие

---
