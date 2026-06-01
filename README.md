# Super App — Личный дашборд

Full-stack веб-приложение: Flutter Web (фронтенд) + FastAPI (бекенд) + PostgreSQL.

**URL**: [pfumiko.ru](https://pfumiko.ru)

---

## Возможности

- 🏠 **Главная** — дашборд с плитками быстрого доступа
- 📈 **Трейдинг** — запуск торговых стратегий (RSI, MACD, Bollinger, SMA/EMA) на реальных данных Binance/Bybit
- 🤖 **Агенты** — мониторинг 20 AI-агентов (статусы, токены, стоимость)
- 🧠 **Второй мозг** — граф заметок с force-directed визуализацией
- 🔑 **DeepSeek** — баланс API DeepSeek
- 🎵 **Музыка** / 🎬 **Видео** — медиа-разделы
- 🌙 **Тёмная/светлая тема** — три режима (тёмная, системная, светлая)
- 📱 **Адаптивный дизайн** — десктоп (сайдбар) + мобила (бургер-меню)
- ⌨️ **Горячие клавиши** — `Ctrl+1/2/3/L`, `Esc`

---

## 🚀 Быстрый старт

### Требования

- **OS**: Linux (Ubuntu 24.04)
- **Python** 3.11+
- **Flutter** 3.7+ (с веб-поддержкой)
- **PostgreSQL** 16
- **Node.js** 18+ (для Hermes, не обязательно)

### 1. База данных

```bash
# Запустить PostgreSQL
sudo systemctl start postgresql

# Создать БД (если нет)
sudo -u postgres createdb super_app
```

### 2. Бекенд

```bash
cd ~/workspace/super-app/backend

# Виртуальное окружение
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt

# Настройки
cp .env.example .env    # или отредактировать существующий .env
# В .env должны быть:
#   DATABASE_URL=postgresql+asyncpg://postgres:postgres@localhost:5432/super_app
#   DEEPSEEK_API_KEY=sk-...
#   SECRET_KEY=...

# Миграции
PYTHONPATH=$PWD alembic upgrade head

# Создать админа
PYTHONPATH=$PWD python3 app/seeds/admin.py

# Запустить сервер
PYTHONPATH=$PWD uvicorn app.main:app --host 0.0.0.0 --port 8000
```

### 3. Фронтенд (Flutter)

```bash
cd ~/workspace/super-app/app

# Собрать веб-версию
flutter build web --release

# Сборка лежит в build/web/
```

### 4. Прокси (шлюз)

```bash
cd ~/workspace/super-app/backend
python3 proxy_server.py
```

Прокси слушает на **`localhost:8790`** и:
- отдаёт статику Flutter из `build/web/`
- проксирует `/api/v1/*` на FastAPI (`:8000`)
- отдаёт Swagger UI `/docs`

### 5. Cloudflare Tunnel (опционально)

```bash
~/.cloudflared/cloudflared tunnel run super-app
# → pfumiko.ru
```

---

## 🌐 Маршруты

| URL | Описание |
|-----|----------|
| `/` | Главный дашборд |
| `/login` | Вход |
| `/register` | Регистрация |
| `/trading` | Трейдинг (список запусков) |
| `/trading/wizard` | Мастер создания стратегии |
| `/trading/runs/:id` | Детали запуска |
| `/admin/agents` | Мониторинг AI-агентов |
| `/admin/deepseek-balance` | Баланс DeepSeek API |
| `/admin/brain` | Второй мозг (граф заметок) |
| `/docs` | Swagger API документация |
| `/health` | Health check бекенда |

---

## ⌨️ Горячие клавиши

| Клавиша | Действие |
|---------|----------|
| `Esc` | ← Назад |
| `Ctrl+1` | 🏠 Главная |
| `Ctrl+2` | 📈 Трейдинг |
| `Ctrl+3` | 🤖 Агенты |
| `Ctrl+L` | 🔑 Логин |

---

## 🛠️ Разработка

### Структура проекта

```
super-app/
├── backend/             # FastAPI (Python)
│   ├── app/
│   │   ├── core/        # config, database, security, dependencies
│   │   ├── models/      # SQLAlchemy модели
│   │   ├── schemas/     # Pydantic схемы
│   │   ├── api/v1/      # Эндпоинты
│   │   └── services/    # Бизнес-логика
│   ├── alembic/         # Миграции БД
│   ├── scripts/         # Вспомогательные скрипты
│   ├── proxy_server.py  # HTTP/1.0 прокси (Flutter + API)
│   └── .env             # Конфигурация
├── app/                 # Flutter (Dart)
│   ├── lib/
│   │   ├── core/        # theme, dio, router, storage
│   │   ├── features/    # auth, home, admin, trading
│   │   ├── models/      # DTO
│   │   └── shared/      # Переиспользуемые виджеты
│   └── build/web/       # Собранный фронтенд
├── CHANGELOG.md         # История изменений
├── ATOM.md              # Техническая сводка
└── README.md            ← Этот файл
```

### Технологии

| Компонент | Стек |
|-----------|------|
| **Фронтенд** | Flutter 3.7+, Dart, Dio, GoRouter, Provider |
| **Бекенд** | FastAPI, SQLAlchemy 2.0 (async), Alembic, Pydantic v2 |
| **БД** | PostgreSQL 16 |
| **Кэш** | Redis (планируется) |
| **Прокси** | Python BaseHTTPRequestHandler (HTTP/1.0) |
| **Туннель** | Cloudflare Tunnel |
| **Иконки** | Phosphor Icons Fill |
| **AI** | DeepSeek V4 Pro/Flash, Agent Control Room (20 агентов) |

### Частые проблемы

**Белый экран / нет обновлений**
```bash
# Сбросить кэш Flutter и пересобрать
cd ~/workspace/super-app/app
flutter clean && flutter pub get && flutter build web --release

# Или открыть в инкогнито / Ctrl+Shift+R
```

**Прокси не стартует**
```bash
# Проверить, не занят ли порт
ss -tlnp | grep 8790

# Убить старый процесс
kill $(ps aux | grep proxy_server | grep -v grep | awk '{print $2}')
```

**Backend не отвечает (502)**
```bash
# Проверить, запущен ли uvicorn
ps aux | grep uvicorn

# Проверить health
curl -s http://localhost:8000/health

# Перезапустить
kill $(ps aux | grep 'uvicorn app.main:app' | grep -v grep | awk '{print $2}')
cd ~/workspace/super-app/backend
PYTHONPATH=$PWD uvicorn app.main:app --host 0.0.0.0 --port 8000
```

**DeepSeek страница показывает ошибку**
```bash
# Проверить ключ в .env
grep DEEPSEEK_API_KEY ~/workspace/super-app/backend/.env

# Если нет — добавить: DEEPSEEK_API_KEY=sk-...
```

### Полезные команды

```bash
# Пересобрать всё сразу
cd ~/workspace/super-app/app && flutter build web --release
# Прокси подхватит автоматически

# Логировать изменения
bash ~/workspace/super-app/scripts/log.sh feat "Что сделано"

# Статус всех процессов
ps aux | grep -E "(uvicorn|proxy_server|postgres)" | grep -v grep
```

---

## 📋 Тестовый доступ

- **Username**: `admin`
- **Пароль**: `admin123`
- **Роль**: admin (все разделы)

---

## 📄 Лицензия

MIT — internal use.
