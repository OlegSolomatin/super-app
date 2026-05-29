# CHANGELOG — Super-App + Agent Control Room

Формат: `[дата] [тип] что сделано | кем`

Типы:
- `feat` — новая фича
- `fix` — исправление
- `agent` — изменения в агентах/профилях
- `docs` — документация
- `infra` — инфраструктура

---
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
