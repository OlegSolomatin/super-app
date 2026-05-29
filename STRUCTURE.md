# Полная структура проекта Super-App

## 🗂 Где что лежит и где что собирается

| Директория | Назначение | Сборка |
|-----------|-----------|--------|
| `~/workspace/super-app/` | **Корень проекта** — документация | — |
| `backend/` | **Python/FastAPI бэкенд** | `docker build` или `uvicorn app.main:app` |
| `backend/app/` | 🟢 Рабочая директория backend (все правки тут) | — |
| `app/` | **Flutter/Dart клиент** | `flutter build apk/ios/web/linux` |
| `app/lib/` | 🟢 Рабочая директория Flutter (все правки тут) | — |
| `app/build/` | ⚠️ Сгенерировано — НЕ редактировать | `flutter build` |
| `app/android/` | 🟢 Android платформа (можно править) | — |
| `app/ios/` | 🟢 iOS платформа (только на macOS) | — |
| `app/web/` | ⚠️ Сгенерировано при сборке | `flutter build web` |
| `app/linux/` | 🟢 Linux Desktop | — |
| `app/windows/` | 🟢 Windows Desktop | — |
| `app/macos/` | 🟢 macOS Desktop | — |
| `shared/` | OpenAPI спецификация, макеты | — |

## 🚫 Чего НЕ делать (чтобы не было дублирования)

- **НЕ создавать** второй `backend/` или `frontend/` рядом — только один
- **НЕ редактировать** `app/build/`, `app/web/` — они генерируются
- **НЕ копировать** файлы из `frontend-new/` (crypto-ton dashboard) в `super-app/` — это разные проекты
- **НЕ путать** `~/workspace/crypto-ton/frontend/` (старый дашборд) с `~/workspace/super-app/` (новый проект)

## 📂 Полная структура

```
~/workspace/super-app/
│
├── docker-compose.yml           # PostgreSQL + Redis + MinIO + backend
├── docker-compose.prod.yml      # + nginx
├── Makefile                     # dev, build, test, migrate
├── README.md                    # Главный README
├── PLAN.md                      # План реализации (индекс)
├── ARCHITECTURE.md              # Архитектура
├── DB.md                        # Схема БД
├── API.md                       # API эндпоинты
├── CODESTYLE.md                 # Правила написания кода
│
├── backend/                     # ← ТОЛЬКО ТУТ ПРАВКИ BACKEND
│   ├── Dockerfile
│   ├── requirements.txt
│   ├── alembic.ini
│   ├── alembic/
│   │   ├── env.py
│   │   └── versions/
│   │
│   └── app/                     # 🟢 FastAPI код (все изменения тут)
│       ├── __init__.py
│       ├── main.py              # FastAPI app
│       │
│       ├── core/
│       │   ├── __init__.py
│       │   ├── config.py        # Настройки (.env)
│       │   ├── database.py      # Async engine
│       │   ├── security.py      # JWT + bcrypt
│       │   └── dependencies.py  # DI
│       │
│       ├── models/              # SQLAlchemy
│       │   ├── __init__.py
│       │   ├── user.py
│       │   ├── post.py
│       │   ├── workout.py
│       │   ├── track.py
│       │   ├── playlist.py
│       │   ├── media_file.py
│       │   └── comment.py
│       │
│       ├── schemas/             # Pydantic
│       │   ├── __init__.py
│       │   ├── auth.py
│       │   ├── post.py
│       │   ├── workout.py
│       │   ├── track.py
│       │   └── media.py
│       │
│       ├── api/
│       │   ├── __init__.py
│       │   ├── router.py
│       │   └── v1/
│       │       ├── __init__.py
│       │       ├── auth.py
│       │       ├── users.py
│       │       ├── posts.py
│       │       ├── workouts.py
│       │       ├── music.py
│       │       ├── video.py
│       │       └── tracks.py
│       │
│       ├── services/
│       │   ├── __init__.py
│       │   ├── auth_service.py
│       │   ├── post_service.py
│       │   ├── workout_service.py
│       │   ├── media_service.py
│       │   └── tracking_service.py
│       │
│       └── tests/
│           ├── conftest.py
│           ├── test_auth.py
│           ├── test_posts.py
│           └── test_workouts.py
│
├── app/                          # ← ТОЛЬКО ТУТ ПРАВКИ FLUTTER
│   ├── pubspec.yaml
│   ├── android/                  # 🟢 Android настройки
│   ├── ios/                      # 🟢 iOS настройки (только macOS)
│   ├── web/                      # ⚠️ Сборка, не править
│   ├── linux/                    # 🟢 Linux Desktop
│   ├── windows/                  # 🟢 Windows Desktop
│   ├── macos/                    # 🟢 macOS Desktop
│   │
│   └── lib/                      # 🟢 Dart код (все изменения тут)
│       ├── main.dart
│       │
│       ├── core/
│       │   ├── theme.dart       # Тёмная тема
│       │   ├── constants.dart   # URL API
│       │   └── router.dart      # GoRouter
│       │
│       ├── services/            # API клиенты
│       │   ├── api_client.dart  # Dio instance
│       │   ├── auth_service.dart
│       │   ├── post_service.dart
│       │   ├── workout_service.dart
│       │   ├── music_service.dart
│       │   ├── video_service.dart
│       │   └── tracking_service.dart
│       │
│       ├── models/              # Dart модели
│       │   ├── user.dart
│       │   ├── post.dart
│       │   ├── workout.dart
│       │   ├── track.dart
│       │   ├── playlist.dart
│       │   └── media_file.dart
│       │
│       ├── providers/           # Riverpod
│       │   ├── auth_provider.dart
│       │   ├── feed_provider.dart
│       │   ├── workout_provider.dart
│       │   └── player_provider.dart
│       │
│       └── screens/             # Экраны
│           ├── auth/
│           │   ├── login_screen.dart
│           │   └── register_screen.dart
│           │
│           ├── social/
│           │   ├── feed_screen.dart
│           │   ├── create_post_screen.dart
│           │   └── post_detail_screen.dart
│           │
│           ├── training/
│           │   ├── workout_list_screen.dart
│           │   ├── workout_detail_screen.dart
│           │   └── create_workout_screen.dart
│           │
│           ├── music/
│           │   ├── music_library_screen.dart
│           │   ├── now_playing_screen.dart
│           │   └── playlist_screen.dart
│           │
│           ├── video/
│           │   ├── video_list_screen.dart
│           │   └── video_player_screen.dart
│           │
│           ├── maps/
│           │   ├── map_screen.dart
│           │   ├── track_detail_screen.dart
│           │   └── recording_screen.dart
│           │
│           └── profile/
│               └── profile_screen.dart
│
└── shared/                       # Общее
    ├── api-spec.yaml             # OpenAPI
    └── design/                   # Макеты
```
