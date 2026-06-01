# CHANGELOG — Super-App + Agent Control Room

Формат: `[дата] [тип] что сделано | кем`

Типы:
- `feat` — новая фича
- `fix` — исправление
- `agent` — изменения в агентах/профилях
- `docs` — документация
- `infra` — инфраструктура
---
- `fix` Кнопка выхода в сайдбаре: тема + выход в одной pinned строке снизу — гарантированно видна на любом экране | Hermes
- `docs` Создан README.md (полное руководство по запуску). Обновлён ATOM.md (актуальные порты, структура, команды). | Hermes
- `feat` Кнопка выхода закреплена вне скролла сайдбара (тема + выход внизу, всегда видны). | Hermes
- `feat` Кнопка выхода в сайдбаре десктопа (внизу) + низ бургер-меню мобилы. Clean build v27 для сброса SW кэша. | Hermes
- `feat` Кнопка выхода: сайдбар десктопа + низ бургер-меню. onLogout в AdaptiveScaffold. | Hermes
- `feat` Fix agents page scrolling + keyboard shortcuts (Esc, Ctrl+1/2/3/L) | Hermes
- `feat` Guest view for unauthenticated users + auth PopupMenuButton | Hermes
- `feat` Auto redirect HTTP→HTTPS via X-Forwarded-Proto header — pfumiko.ru всегда форсирует HTTPS | Hermes
- `fix` Proxy: HTTP/1.0 + proxy /auth/* routes — fixes login timeout through super-app proxy | Hermes
- `fix` HTTP/1.1 keep-alive in proxy + clean restart — fixes Cloudflare errors and stale cache | Hermes
- `fix` Rebuild v23 — full restart (clean cloudflared + proxy), email → username login | Hermes
- `feat` Replace email login field with username — backend + frontend | Hermes
- `fix` Fix centering of dashboard tiles — replaced GridView with Wrap in ResponsiveGrid | Hermes

## 2026-05-30

- `infra` Оптимизация загрузки: gzip-сжатие статики в proxy (JS/WASM/CSS —70%), Cache-Control immutable на год, preload main.dart.js + canvaskit.wasm в index.html | Hermes
- `fix` Сплэш-скрин: теперь ждёт первый кадр Flutter (canvas/flt-glass-pane) вместо window.load — убран пустой экран между сплэшем и приложением | Hermes

- `refactor` DashboardTile вынесен в отдельный виджет `lib/shared/widgets/dashboard_tile.dart` — единый стиль для всех плиток (центрирование, иконка, текст, анимации). Новая плитка = одна строка `DashboardTileData(...)` | Hermes

- `feat` Граф Мозга: InteractiveViewer (pinch-zoom, pan, scroll-zoom), force-directed расталкивание 30k, авто-fit на экран, адаптация под мобилу (узлы 32px, метки компактнее) | Hermes
- `feat` Второй мозг: страница `/admin/brain` с графом (force-directed) и лентой (поиск, сортировка по дате) — админ-плитка + навдестинация | Hermes
- `fix` Чистка хедера: убраны иконки темы, агентов и выхода — только заголовок + бургер | Hermes
- `fix` Центрирование текста в плитках на главной (FittedBox, mainAxisSize: min, убран maxLines) | Hermes
- `fix` DeepSeek баланс: 502 ошибка из-за отсутствия DEEPSEEK_API_KEY в env процесса — сервер перезапущен с ключом | Hermes
- `fix` AgentsPage + LoginPage обёрнуты в ConstrainedContent для адаптивности | Hermes
- `infra` Бэкенд: эндпоинты `/admin/brain/graph` (GET) и `/admin/brain/status` (POST) — смена статуса заметок через frontmatter + регенерация графа | Hermes

## 2026-05-29

- `feat` DeepSeek API balance — admin page + tile on HomePage | Hermes
- `fix` PnL sign fix in history tab — always showed '+' even for negative values | Hermes
- `feat` Splash screen loader in index.html. responsive fix for WizardPage + DashboardCards | Hermes
- `feat` WizardPage wrapped in ConstrainedContent. DashboardCards crossAxisAlignment fix | Hermes
- `feat` Responsive desktop layout. responsive_layout, adaptive_scaffold, responsive_grid. LoginPage centered card, HomePage with sidebar+grid. TradingPage/AgentsPage constrained. Build v11 | Hermes
- `feat` Phase 12: Trading Module — backend (22 файла, 9 API, индикаторы RSI/SMA/EMA/MACD/Bollinger, стратегии Hammer+Inverse Hammer) | Hermes
- `feat` Phase 12: Flutter — главная торговли (табы), 9-шаговый мастер, страница деталей запуска | Hermes
- `feat` Material icons → Phosphor Icons Fill (robot, fileText, barbell, musicNotes, videoCamera, mapPin) | Hermes
- `fix` Card text centering: textAlign.center на заголовки, убрана фоновая иконка | Hermes
- `fix` Theme sync: login, register, agents pages now use Theme.of(context) — light/dark applies globally | Hermes
- `feat` Дизайн-рефреш: карточки с border/shadow, scale-анимация, staggered fade-in | Hermes
- `feat` Бургер-меню (endDrawer): профиль, меню, logout, переключатель темы внизу | Hermes
- `feat` Светлая тема: #F5F5FA, белые карточки, тёмный текст | Hermes
- `feat` ThemeProvider: три режима (dark/system/light) с сохранением в SharedPreferences | Hermes
- `fix` HomePage: отступ SizedBox теперь внутри if (_showBanner) — нет пустого места после скрытия | Hermes
- `fix` HomePage: таймер баннера стартует после загрузки профиля (не в initState) | Hermes
- `fix` AgentsPage: Navigator.pop → context.go('/') (GoRouter совместимость) | Hermes
- `feat` HomePage: welcome banner auto-hide через 15 секунд с FadeTransition | Hermes
- `fix` users.py: добавлен импорт selectinload (NameError), добавлена загрузка ролей в GET /users/me | Hermes
- `fix` User model: int id → String id (ошибка type 'String' is not subtype of type 'num' с UUID от API) | Hermes
- `fix` Flutter: добавлено поле roles в User модель (проверка на admin) | Hermes
- `feat` Phase 11: Flutter — админ-тил на HomePage + страница /admin/agents с анимацией статусов | Hermes
- `feat` Phase 11: backend — collect_agent_stats.py + GET /admin/agents/status (20 агентов, статусы, токены) | Hermes
- `docs` PLAN.md: добавлена Фаза 11 с детальным описанием, источниками данных и интеграцией с Agent Control Room | Hermes
- `feat` Фаза 11: Agent Monitoring Dashboard — админ-панель мониторинга агентов (статусы, токены, задачи) | Hermes
- `fix` White page/502: backend 500 из-за UUID → str, несовместимость secure_storage с web | Hermes
- `fix` UserRead.id: UUID → str в Pydantic схеме (ошибка 500 при сериализации UUID) | Hermes
- `fix` Flutter web: flutter_secure_storage → shared_preferences (совместимость с браузером) | Hermes
- `fix` Flutter web: baseUrl localhost:8000 → /api/v1 (работа через прокси) | Hermes
- `docs` ATOM.md — тех. сводка (порты, БД, запуск) + добавлен в .gitignore | Hermes
- `fix` security.py: passlib → прямой bcrypt (совместимость с Python 3.14) | Hermes
- `infra` super-app запущен на pfumiko.ru через Cloudflare Tunnel (Flutter web + FastAPI API) | Hermes
- `feat` Phase 3: Flutter MVP — auth (login/register), dashboard, Dio client, GoRouter, Riverpod, тёмная тема (18 файлов) | flutter-coder
- `feat` Phase 2: профиль (PATCH /me) + уведомления + Redis кэш + админка (18 файлов) | backend-coder
- `fix` security.py: get_password_hash (вместо hash_password), create_access_token теперь принимает subject= вместо data= | Hermes
- `agent` включены релевантные скиллы 19 агентам (вместо skip: true) | Hermes
- `feat` backend scaffold: FastAPI + SQLAlchemy 2.0 async + JWT + Alembic + Docker (28 файлов) | backend-coder
- `infra` обновлён sw.js в frontend/ (новая Workbox-версия) | Hermes
- `infra` настроен cron daily-backup (конфиги, каждый день в 3:00) | Hermes
- `infra` отключены skills у 19 профилей агентов (экономия ~15с на старт) | Hermes
- `infra` увеличены лимиты памяти: memory 5000→10000, user 2500→5000 | Hermes
- `infra` создан .gitignore (secrets, Python, Flutter, Node, IDE, OS, backups) | Hermes

## 2026-05-28

- `agent` Созданы профили `flutter-coder` и `backend-coder` для super-app | Hermes
- `agent` Coder: смена модели qwen3-coder → deepseek-v4-flash + новый SOUL.md | Hermes
- `agent` Designer: смена модели mistral → deepseek-v4-flash + ключ + SOUL.md | Hermes
- `agent` Screen-analyzer: удалён (не нужен) | Hermes
- `agent` Data-analyst, devops, preloader, trading-analyst: переведены с OpenRouter на прямой DeepSeek API | Hermes
- `agent` Planner: max_turns 20→50, clarify выключен | Hermes
- `agent` Всем 8 агентам (reviewer, reporter, tester, cost-tracker, security-auditor, technical-writer, health-monitor, default) написаны полноценные Job Description | Hermes
- `infra` Pipeline.sh обновлён до v5 — передача контекста между агентами, Shared Knowledge, reviewer после каждого шага | Hermes
- `infra` Создан bus/knowledge.yaml — общая память агентов | Hermes
- `infra` Создан bus/update_knowledge.sh — скрипт обновления знаний | Hermes
- `infra` Dispatch.sh обновлён — читает knowledge.yaml и outbox других агентов перед запуском | Hermes
- `infra` Agents.yaml: 20 агентов, все модели актуальны | Hermes
- `docs` Создан ~/workspace/super-app/ — полная документация (PLAN, ARCHITECTURE, STRUCTURE, DB, API, CODESTYLE) | Hermes
- `docs` Добавлен Code Style Guide в PLAN.md (Python + Dart правила) | Hermes
- `docs` STRUCTURE.md — указаны рабочие директории и запреты на дублирование | Hermes
- `feat` BinanceExchange — реальные исторические свечи через публичный API (get_klines с пагинацией) | Hermes
- `feat` BybitExchange — реальные исторические свечи через публичный API v5 | Hermes
- `fix` DataLoader — принимает exchange_name, по умолчанию binance (вместо mock) | Hermes
- `fix` DataLoader — исправлено сравнение offset-naive/offset-aware datetime | Hermes
- `fix` Scheduler — передаёт exchange_name в DataLoader | Hermes
- `fix` Trading API — добавлен eager load result+trades (MissingGreenlet fix) | Hermes
- `feat` Trading page — polling активных запусков (каждые 2 сек), автообновление истории | Hermes
- `build` PWA v1.0.0+10 | Hermes
- `feat` Virtual mode — real-time candle delays (asyncio.sleep между свечами) | Hermes
- `feat` Virtual live — live paper trading (polling Binance каждые N секунд, real-time) | Hermes
- `feat` Virtual live — таймаут по duration_days + прогресс-бар с таймером в UI | Hermes
- `fix` Детали сделки — дата/время входа и выхода в карточке сделки | Hermes
- `fix` Список пар — pageSize 50 (вместо 20), lazy load по 50 при скролле | Hermes
