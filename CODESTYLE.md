# Code Style Guide — Super-App

## 1. Общие принципы

| Принцип | Что значит |
|---------|-----------|
| **DRY** | Не повторяй код. Общее — в функции/компоненты/виджеты |
| **YAGNI** | Не пиши то, что не нужно сейчас. Нет «на будущее» |
| **KISS** | Проще = лучше. Если можно в 5 строк — не пиши 20 |
| **Single Responsibility** | Одна функция/компонент — одна задача |
| **Clean Architecture** | Разделение на слои: API → Service → Repository → UI |

## 2. Именование

### Backend (Python)
| Что | Правило | Пример |
|-----|---------|--------|
| Файлы | snake_case | `user_service.py`, `auth_router.py` |
| Классы | PascalCase | `class UserService` |
| Функции | snake_case | `def get_user()` |
| Переменные | snake_case | `user_id` |

### Flutter (Dart)
| Что | Правило | Пример |
|-----|---------|--------|
| Файлы | snake_case | `login_screen.dart` |
| Классы | PascalCase | `class LoginScreen` |
| Функции | camelCase | `void fetchData()` |
| Переменные | camelCase | `final userId` |

## 3. Python (FastAPI)

```python
# ✅ Хорошо
@router.post("/", response_model=UserResponse)
async def create_user(data: UserCreate, service: UserService = Depends()):
    """Создать нового пользователя."""
    return await service.create(data)

# ❌ Плохо
@router.post("/")
async def create_user(data: dict):  # нет типов!
    ...
```

**Правила:**
- Все роутеры асинхронные (`async def`)
- Все эндпоинты типизированные (Pydantic на вход/выход)
- Бизнес-логика в services/, не в роутерах
- Каждый эндпоинт с docstring

## 4. Flutter (Dart)

```dart
// ✅ Хорошо
final feedProvider = FutureProvider.family<List<Post>, FeedFilter>((ref, filter) async {
  final api = ref.read(apiClientProvider);
  return api.getFeed(filter);
});

class FeedScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feedAsync = ref.watch(feedProvider(FeedFilter.latest));
    return feedAsync.when(
      data: (posts) => ListView.builder(...),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorWidget(e.toString()),
    );
  }
}
```

**Правила:**
- Все экраны — ConsumerWidget (Riverpod)
- Никаких setState для данных с API
- Каждый запрос через Dio
- Состояния: Loading / Error / Empty / Data

## 5. Обработка ошибок

### Backend
```python
class AppException(HTTPException):
    def __init__(self, code: str, message: str, status: int = 400):
        super().__init__(status_code=status, detail={"code": code, "message": message})
```

### Flutter
```dart
data.when(
  data: (value) => ...,
  loading: () => const LoadingWidget(),
  error: (e, stack) => ErrorWidget(message: e.toString()),
);
```

## 6. Git-коммиты

| Тип | Когда | Пример |
|-----|-------|--------|
| `feat:` | Новая фича | `feat: add user registration` |
| `fix:` | Баг | `fix: handle empty feed` |
| `refactor:` | Рефакторинг | `refactor: extract auth service` |
| `docs:` | Документация | `docs: add API endpoints` |
| `chore:` | Инфраструктура | `chore: setup CI/CD` |

## 7. Тестирование
- Backend: pytest + httpx, тест на каждый эндпоинт
- Flutter: widget-тесты на каждый экран, unit-тесты на сервисы
