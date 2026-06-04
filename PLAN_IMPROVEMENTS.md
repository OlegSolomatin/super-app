# План улучшений super-app

> Основан на анализе `fastapi-best-practices` (12.5k ⭐),
> `full-stack-fastapi-template` (31k ⭐) и `very_good_flutter_boilerplate` (800+ ⭐).
>
> Создан: 01.06.2026

---

## Содержание

- [Легенда](#-легенда)
- [Фаза 1: Backend — CRUD + Services + Error Handler](#-фаза-1-backend--crud--services--error-handler)
- [Фаза 2: Backend — N+1 + Rate Limiting + CI/CD](#-фаза-2-backend--n1--rate-limiting--cicd)
- [Фаза 3: Flutter — Bloc для Trading](#-фаза-3-flutter--bloc-для-trading)
- [Фаза 4: Flutter — Lint + Тесты + Freezed](#-фаза-4-flutter--lint--тесты--freezed)
- [Фаза 5: Flutter — Domain слой (рефактор)](#-фаза-5-flutter--domain-слой-рефактор)

---

## 📋 Легенда

| Метка | Значение |
|-------|----------|
| 🔴 High | Критично для архитектуры |
| 🟡 Medium | Важно, но не срочно |
| 🟢 Nice | Опционально |
| ⏱ | Оценка времени |
| 📁 | Какие файлы трогать |

---

## 🔷 Фаза 1: Backend — CRUD + Services + Error Handler

**⏱ 3-4 часа · 🔴 High**

### 1.1 Создать слой `app/crud/`

```
backend/app/
└── crud/
    ├── __init__.py
    ├── base.py          # Generic CRUD (create, get, update, delete, list)
    ├── user.py          # CRUDUser: get_by_email, get_by_id, create
    └── trading_run.py   # CRUDTradingRun: get_active, get_history, get_by_strategy
```

**base.py** — generic base class:
```python
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func
from app.models.base import Base

class CRUDBase[ModelT: Base]:
    def __init__(self, model: type[ModelT]):
        self.model = model

    async def get(self, db: AsyncSession, id: UUID) -> ModelT | None:
        result = await db.execute(select(self.model).where(self.model.id == id))
        return result.scalar_one_or_none()

    async def get_multi(
        self, db: AsyncSession, *, skip: int = 0, limit: int = 100
    ) -> list[ModelT]:
        result = await db.execute(
            select(self.model).offset(skip).limit(limit)
        )
        return list(result.scalars().all())

    async def create(self, db: AsyncSession, obj_in: BaseModel) -> ModelT:
        obj = self.model(**obj_in.model_dump())
        db.add(obj)
        await db.commit()
        await db.refresh(obj)
        return obj
```

**user.py:**
```python
class CRUDUser(CRUDBase[User]):
    async def get_by_email(self, db: AsyncSession, email: str) -> User | None:
        result = await db.execute(select(User).where(User.email == email))
        return result.scalar_one_or_none()

    async def get_by_token(self, db: AsyncSession, token: str) -> User | None:
        result = await db.execute(
            select(User).where(User.access_token == token)
        )
        return result.scalar_one_or_none()
```

**trading_run.py:**
```python
class CRUDTradingRun(CRUDBase[TradingRun]):
    async def get_active(self, db: AsyncSession) -> list[TradingRun]:
        result = await db.execute(
            select(TradingRun)
            .where(TradingRun.status.in_(["running", "pending"]))
            .order_by(TradingRun.created_at.desc())
        )
        return list(result.scalars().all())

    async def get_history(self, db: AsyncSession, limit: int = 50) -> list[TradingRun]:
        result = await db.execute(
            select(TradingRun)
            .where(TradingRun.status.in_(["done", "stopped", "error"]))
            .order_by(TradingRun.created_at.desc())
            .limit(limit)
        )
        return list(result.scalars().all())
```

### 1.2 Создать слой `app/services/`

```
backend/app/
└── services/
    ├── __init__.py
    ├── auth.py          # authenticate_user, register_user
    └── trading.py       # run_strategy, stop_strategy, get_scan_progress
```

**auth.py:**
```python
from app.crud.user import CRUDUser
from app.core.security import verify_password, create_access_token

class AuthService:
    def __init__(self, crud_user: CRUDUser):
        self.crud = crud_user

    async def authenticate(self, db: AsyncSession, email: str, password: str) -> User | None:
        user = await self.crud.get_by_email(db, email)
        if not user or not verify_password(password, user.hashed_password):
            return None
        return user

    async def login(self, db: AsyncSession, email: str, password: str) -> dict | None:
        user = await self.authenticate(db, email, password)
        if not user:
            return None
        token = create_access_token(subject=user.id)
        return {"access_token": token, "token_type": "bearer"}
```

### 1.3 Создать единый error handler

**📁 `app/core/exceptions.py`:**
```python
class AppException(Exception):
    """Base application exception."""
    def __init__(self, detail: str, status_code: int = 400):
        self.detail = detail
        self.status_code = status_code

class NotFoundException(AppException):
    def __init__(self, detail: str = "Resource not found"):
        super().__init__(detail, status_code=404)

class UnauthorizedException(AppException):
    def __init__(self, detail: str = "Not authenticated"):
        super().__init__(detail, status_code=401)

class ForbiddenException(AppException):
    def __init__(self, detail: str = "Not enough permissions"):
        super().__init__(detail, status_code=403)

class ConflictException(AppException):
    def __init__(self, detail: str = "Resource already exists"):
        super().__init__(detail, status_code=409)
```

**📁 В `app/main.py` добавить глобальный хендлер:**
```python
@app.exception_handler(AppException)
async def app_exception_handler(request: Request, exc: AppException):
    return JSONResponse(
        status_code=exc.status_code,
        content={
            "detail": exc.detail,
            "code": exc.__class__.__name__,
        },
    )

@app.exception_handler(ValidationError)
async def validation_exception_handler(request: Request, exc: ValidationError):
    return JSONResponse(
        status_code=422,
        content={
            "detail": exc.errors(),
            "code": "ValidationError",
        },
    )
```

### 1.4 Переписать API роуты — тонкие слои

Каждый роут теперь:
1. Принимает Pydantic-схему
2. Зовёт сервис
3. Возвращает ответ

**📁 `app/api/v1/endpoints/trading.py` — пример:**
```python
@router.get("/runs", response_model=PaginatedResponse[TradingRunResponse])
async def get_runs(
    status: str | None = None,
    skip: int = 0,
    limit: int = 20,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if status == "running":
        runs = await crud_trading_run.get_active(db)
    elif status in ("done", "stopped", "error"):
        runs = await crud_trading_run.get_history(db, limit)
    else:
        runs = await crud_trading_run.get_multi(db, skip=skip, limit=limit)
    return PaginatedResponse(items=runs, total=len(runs))
```

---

## 🔷 Фаза 2: Backend — N+1 + Rate Limiting + CI/CD

**⏱ 2-3 часа · 🟡 Medium**

### 2.1 Защита от N+1 запросов

**📁 Найти все места с загрузкой отношений (trades, user) и добавить `selectinload`**

```python
# В CRUDTradingRun (или напрямую в роуте)
from sqlalchemy.orm import selectinload

result = await db.execute(
    select(TradingRun)
    .options(selectinload(TradingRun.trades))
    .where(TradingRun.id == run_id)
)
```

**Проверить:**
- `TradingRun` → `trades`
- `User` → `runs` (если есть)
- Любые другие `relationship()` в моделях

### 2.2 Rate Limiting — slowapi

**📁 `backend/requirements.txt` (добавить):**
```
slowapi>=0.1.9
```

**📁 `app/core/rate_limit.py`:**
```python
from slowapi import Limiter
from slowapi.util import get_remote_address

limiter = Limiter(key_func=get_remote_address)
```

**📁 В `app/main.py`:**
```python
from app.core.rate_limit import limiter
from slowapi import _rate_limit_exceeded_handler

app.state.limiter = limiter
app.add_exception_handler(429, _rate_limit_exceeded_handler)
```

**📁 На роуты:**
```python
@router.get("/runs")
@limiter.limit("30/minute")
async def get_runs(request: Request, ...):
    ...
```

### 2.3 CI/CD — GitHub Actions

**📁 `.github/workflows/test.yml`:**
```yaml
name: Backend CI
on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:16
        env:
          POSTGRES_USER: test
          POSTGRES_PASSWORD: test
          POSTGRES_DB: test_db
        ports:
          - 5432:5432
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5

    steps:
      - uses: actions/checkout@v4

      - name: Set up Python 3.12
        uses: actions/setup-python@v5
        with:
          python-version: "3.12"

      - name: Install dependencies
        working-directory: backend
        run: |
          python -m pip install --upgrade pip
          pip install -r requirements.txt
          pip install pytest pytest-asyncio pytest-cov httpx

      - name: Lint with ruff
        working-directory: backend
        run: pip install ruff && ruff check .

      - name: Run tests
        working-directory: backend
        env:
          DATABASE_URL: postgresql+asyncpg://test:test@localhost:5432/test_db
        run: pytest --cov=app --cov-report=term-missing -v
```

---

## 🔷 Фаза 3: Flutter — Bloc для Trading

**⏱ 4-5 часов · 🔴 High**

### 3.1 Добавить зависимости

**📁 `app/pubspec.yaml`:**
```yaml
dependencies:
  flutter_bloc: ^8.1.0
  equatable: ^2.0.5

dev_dependencies:
  bloc_test: ^9.1.0
  mocktail: ^1.0.0
```

### 3.2 Создать структуру Bloc в Trading

```
lib/features/trading/
├── bloc/
│   ├── trading_bloc.dart       # TradingBloc
│   ├── trading_event.dart      # TradingEvent
│   ├── trading_state.dart      # TradingState
│   └── trading_bloc_test.dart  # тесты
├── data/
│   └── trading_repository.dart # уже есть
└── presentation/
    ├── trading_page.dart       # переписать с BlocProvider
    ├── wizard_page.dart
    └── run_detail_page.dart
```

### 3.3 TradingState (с Freezed)

**📁 `lib/features/trading/bloc/trading_state.dart`:**
```dart
@freezed
class TradingState with _$TradingState {
  const factory TradingState.initial() = _Initial;
  const factory TradingState.loading() = _Loading;
  const factory TradingState.active(List<TradingRun> runs) = _Active;
  const factory TradingState.history(List<TradingRun> runs) = _History;
  const factory TradingState.error(String message) = _Error;
}
```

### 3.4 TradingEvent

**📁 `lib/features/trading/bloc/trading_event.dart`:**
```dart
@freezed
class TradingEvent with _$TradingEvent {
  const factory TradingEvent.loadActive() = LoadActive;
  const factory TradingEvent.loadHistory() = LoadHistory;
  const factory TradingEvent.pollActive() = PollActive;
  const factory TradingEvent.startRun(Map<String, dynamic> config) = StartRun;
  const factory TradingEvent.stopRun(String runId) = StopRun;
}
```

### 3.5 TradingBloc

**📁 `lib/features/trading/bloc/trading_bloc.dart`:**
```dart
class TradingBloc extends Bloc<TradingEvent, TradingState> {
  final TradingRepository _repository;

  TradingBloc(this._repository) : super(const TradingState.initial()) {
    on<LoadActive>(_onLoadActive);
    on<LoadHistory>(_onLoadHistory);
    on<PollActive>(_onPollActive);
    on<StartRun>(_onStartRun);
    on<StopRun>(_onStopRun);
  }

  Future<void> _onLoadActive(LoadActive event, Emitter<TradingState> emit) async {
    emit(const TradingState.loading());
    try {
      final result = await _repository.getRuns(status: 'running');
      emit(TradingState.active(result.items));
    } catch (e) {
      emit(TradingState.error(e.toString()));
    }
  }

  Future<void> _onPollActive(PollActive event, Emitter<TradingState> emit) async {
    // Silent poll — только если уже был активный стейт
    if (state is _Active) {
      try {
        final result = await _repository.getRuns(status: 'running');
        emit(TradingState.active(result.items));
      } catch (_) {}
    }
  }
}
```

### 3.6 Переписать TradingPage

**📁 `lib/features/trading/presentation/trading_page.dart`:**
```dart
class TradingPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => TradingBloc(repository)..add(const LoadActive()),
      child: _TradingPageView(),
    );
  }
}
```

### 3.7 Тесты Bloc

**📁 `lib/features/trading/bloc/trading_bloc_test.dart`:**
```dart
void main() {
  late MockTradingRepository repository;
  late TradingBloc bloc;

  setUp(() {
    repository = MockTradingRepository();
    bloc = TradingBloc(repository);
  });

  blocTest<TradingBloc, TradingState>(
    'emits [loading, active] when loadActive succeeds',
    build: () => bloc,
    act: (bloc) => bloc.add(const LoadActive()),
    wait: const Duration(milliseconds: 100),
    expect: () => [
      const TradingState.loading(),
      isA<TradingState>().having((s) => s.runs, 'runs', isNotEmpty),
    ],
  );
}
```

---

## 🔷 Фаза 4: Flutter — Lint + Тесты + Freezed

**⏱ 3-4 часа · 🟡 Medium**

### 4.1 Подключить very_good_analysis

**📁 `app/pubspec.yaml`:**
```yaml
dev_dependencies:
  very_good_analysis: ^6.0.0
```

**📁 `app/analysis_options.yaml`:**
```yaml
include: package:very_good_analysis/analysis_options.yaml

linter:
  rules:
    lines_longer_than_80_chars: false  # Отключить для гибкости
    public_member_api_docs: false      # Отключить до полного документирования
```

**После подключения:** запустить `dart analyze` и исправить ~30-50 замечаний:
- `avoid_print` → заменить на `debugPrint()` или `log()`
- `prefer_const_constructors` → добавить const
- `always_use_package_imports` → исправить относительные импорты

### 4.2 Структура тестов

```
test/
├── helpers/
│   ├── mocks.dart           # Mockito/mocktail моки
│   └── pump_app.dart        # WidgetTester helper с Provider/Bloc
├── features/
│   ├── trading/
│   │   ├── bloc/
│   │   │   └── trading_bloc_test.dart
│   │   └── view/
│   │       └── trading_page_test.dart
│   └── auth/
│       └── ...
└── shared/
    ├── widgets/
    │   └── pf_card_test.dart
    └── tokens/
        └── pf_colors_test.dart
```

### 4.3 Freezed для всех стейтов

**Где добавить:**
- `TradingState` (уже описан в Фазе 3)
- `AuthState` — login, register
- `UserState` — если Provider меняется на Bloc

**Пример:**
```dart
@freezed
class AuthState with _$AuthState {
  const factory AuthState.initial() = _Initial;
  const factory AuthState.loading() = _Loading;
  const factory AuthState.authenticated(User user) = _Authenticated;
  const factory AuthState.unauthenticated() = _Unauthenticated;
  const factory AuthState.error(String message) = _Error;
}
```

---

## 🔷 Фаза 5: Flutter — Domain слой (рефактор)

**⏱ 1-2 часа · 🟢 Nice**

### 5.1 Аудит use cases

**Проверить `lib/features/*/domain/usecases/`:**
- Какие use cases реально содержат бизнес-логику?
- Какие просто проксируют repository → Bloc?

**Оставить (сложная логика):**
- `ValidateOrderUseCase` — расчёт комиссий, лимитов
- `ProcessTradeSignalUseCase` — обработка сигнала перед ордером

**Удалить / встроить в Bloc (простые CRUD):**
- `GetRunsUseCase` → просто вызов репозитория из Bloc
- `CreateUserUseCase` → просто вызов репозитория из Bloc

### 5.2 Новая структура (после рефактора)

```
lib/features/trading/
├── bloc/              ← бизнес-логика здесь (Bloc)
├── data/
│   ├── models/        ← TradingRun (DTO)
│   ├── repositories/  ← TradingRepository
│   └── datasources/   ← API источники
├── domain/
│   ├── entities/      ← TradingRunEntity (если нужна изоляция)
│   └── usecases/      ← только сложные (ValidateOrder)
└── presentation/      ← UI + страницы
```

---

## 📌 Сводная таблица

| № | Задача | Фаза | Приоритет | Время | Кому |
|---|--------|------|-----------|-------|------|
| 1 | CRUD слой | 1 | 🔴 | 1-2ч | Backend |
| 2 | Services слой | 1 | 🔴 | 1ч | Backend |
| 3 | Error handler | 1 | 🔴 | 1ч | Backend |
| 4 | Тонкие API роуты | 1 | 🔴 | 1ч | Backend |
| 5 | N+1 защита | 2 | 🟡 | 30м | Backend |
| 6 | Rate limiting | 2 | 🟡 | 30м | Backend |
| 7 | CI/CD | 2 | 🟡 | 1ч | Backend |
| 8 | Bloc для Trading | 3 | 🔴 | 4-5ч | Flutter |
| 9 | very_good_analysis | 4 | 🟡 | 1-2ч | Flutter |
| 10 | Тесты | 4 | 🟡 | 3-4ч | Flutter |
| 11 | Freezed стейты | 4 | 🟡 | 1ч | Flutter |
| 12 | Domain рефактор | 5 | 🟢 | 1-2ч | Flutter |

**Итого: ~15-20 часов работы**

---

## 🚀 Рекомендуемый порядок выполнения

```
Неделя 1:
  └─ Фаза 1 (Backend: CRUD + Services + Error Handler) — 3-4ч
      → Сразу видно: чистая структура, стабильные ошибки

Неделя 2:
  ├─ Фаза 3 (Flutter: Bloc для Trading) — 4-5ч
  │   → Bloc даёт устойчивость асинхронному Trading
  └─ Фаза 4 (Flutter: Lint) — 1-2ч
      → Чистота кода сразу

Неделя 3:
  ├─ Фаза 2 (Backend: N+1 + Rate Limiting + CI/CD) — 2-3ч
  └─ Фаза 4 (Flutter: Тесты) — 3-4ч

Неделя 4:
  ├─ Фаза 4 (Flutter: Freezed стейты) — 1ч
  └─ Фаза 5 (Flutter: Domain рефактор) — 1-2ч
```
