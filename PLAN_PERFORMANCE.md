# План оптимизации загрузки Flutter Web

> Основан на анализе репозиториев и инструментов.
> Текущая проблема: долгая загрузка (`main.dart.js` ~2-3MB, FCP >3-5 секунд)
>
> Создан: 01.06.2026

---

## Содержание

- [Замеры текущей производительности](#-замеры-текущей-производительности)
- [Быстрые победы (1 день)](#-фаза-1-быстрые-победы---1-день)
- [Средний приоритет (2-3 дня)](#-фаза-2-средний-приоритет---2-3-дня)
- [Глубокая оптимизация (неделя)](#-фаза-3-глубокая-оптимизация---неделя)
- [Шпаргалка по командам](#-шпаргалка-по-командам)

---

## 📊 Замеры текущей производительности

Перед началом — замерить текущие метрики:

```bash
# 1. Размер бандла
ls -lh ~/workspace/super-app/app/build/web/main.dart.js
du -sh ~/workspace/super-app/app/build/web/

# 2. FCP/LCP через Lighthouse (в Chrome DevTools)
# или через CLI:
npx lighthouse https://pfumiko.ru/ --view

# 3. Время загрузки через curl
curl -o /dev/null -s -w "time_total: %{time_total}s\n" https://pfumiko.ru/
```

---

## 🔷 Фаза 1: Быстрые победы — 1 день

### 1.1 HTML renderer вместо CanvasKit

**⏱ 5 мин · 🔴 High · Эффект: -30-50% FCP**

Flutter Web имеет два рендерера:
- **HTML** — меньший бандл (~1.4MB), быстрее первый кадр
- **CanvasKit** — полная точность, но ~2.4MB

**Текущий билд:** скорее всего CanvasKit (дефолт). Переключить:

```bash
flutter build web --release --web-renderer html
```

**🔥 Прирост:** бандл меньше на ~40%, FCP быстрее на 30-50%.

**Проверить:** если UI не ломается (первые 3-4 экрана) — оставить HTML. CanvasKit нужен только для сложных анимаций/кастома.

### 1.2 Заменить service worker на Workbox

**⏱ 1 час · 🔴 High · Эффект: последующие загрузки 0ms**

Текущий `flutter_service_worker.js` — минимальный. Перейти на **Workbox** (Google, 12k ⭐):

**📁 `web/` создать кастомный service worker:**

```javascript
// web/sw.js
importScripts('https://storage.googleapis.com/workbox-cdn/releases/6.5.4/workbox-sw.js');

workbox.setConfig({ debug: false });

// Precache app shell (main.dart.js, flutter.js, index.html)
workbox.precaching.precacheAndRoute(self.__WB_MANIFEST || []);

// Кэшировать изображения — Cache First
workbox.routing.registerRoute(
  /\.(?:png|jpg|jpeg|svg|gif|webp|ico)$/,
  new workbox.strategies.CacheFirst({
    cacheName: 'images',
    plugins: [new workbox.expiration.ExpirationPlugin({ maxEntries: 50, maxAgeSeconds: 30 * 24 * 60 * 60 })],
  })
);

// Кэшировать API-ответы — Stale While Revalidate
workbox.routing.registerRoute(
  /\/api\/v1\/(trading|health|status)/,
  new workbox.strategies.StaleWhileRevalidate({
    cacheName: 'api-cache',
    plugins: [new workbox.expiration.ExpirationPlugin({ maxEntries: 30, maxAgeSeconds: 5 * 60 })],
  })
);
```

**🤖 Генерация precache-манифеста:** добавить `workbox-cli` или генерировать скриптом на Python после сборки:

```python
# scripts/generate_sw_manifest.py
import os, json
from pathlib import Path

build_dir = Path.home() / "workspace/super-app/app/build/web"
manifest = []
for f in build_dir.rglob("*"):
    if f.is_file() and not f.name.startswith("."):
        url = str(f.relative_to(build_dir)).replace("\\", "/")
        manifest.append({"url": f"/{url}", "revision": str(os.path.getmtime(f))})

with open(build_dir / "sw_manifest.json", "w") as f:
    json.dump(manifest, f)
```

### 1.3 Native splash screen

**⏱ 30 мин · 🟡 Medium · Эффект: мгновенный визуальный отклик**

**📁 `pubspec.yaml`:**
```yaml
dev_dependencies:
  flutter_native_splash: ^2.3.0
```

**📁 `flutter_native_splash.yaml`:**
```yaml
flutter_native_splash:
  color: "#0B0E11"
  image: assets/splash_logo.png
  android: false
  ios: false
  web: true
  fullscreen: true
```

Генерировать: `dart run flutter_native_splash:create`

**🔥 Прирост:** Пользователь видит логотип сразу после нажатия на ссылку, а не белый экран на 3 секунды.

### 1.4 Preload критических API

**⏱ 15 мин · 🟡 Medium · Эффект: данные приходят на 100-200ms раньше**

**📁 `web/index.html`:**
```html
<head>
  <!-- Preload критических данных -->
  <link rel="preload" href="/api/v1/users/me" as="fetch" crossorigin="anonymous">
  <link rel="preload" href="/api/v1/trading/active" as="fetch" crossorigin="anonymous">

  <!-- Preload основного JS -->
  <link rel="preload" href="main.dart.js" as="script">
  <link rel="preload" href="flutter.js" as="script">
</head>
```

---

## 🔷 Фаза 2: Средний приоритет — 2-3 дня

### 2.1 Deferred imports — ленивая загрузка фич

**⏱ 2-3 часа · 🔴 High · Эффект: -30-60% initial bundle**

**Dart `deferred as`** — разделяет код на отдельные JS-чанки, которые грузятся только при первом обращении.

**Где применить:**

```dart
// Вместо обычного импорта:
import 'package:app/features/admin/agents_page.dart';

// Сделать:
import 'package:app/features/admin/agents_page.dart' deferred as admin;
```

```dart
// Использовать так:
Future<void> _openAdmin() async {
  await admin.loadLibrary();  // ← чанк грузится ТОЛЬКО здесь
  if (mounted) {
    context.go('/admin/agents');
  }
}
```

**Какие фичи вынести в deferred:**
- `/admin/agents` — панель агентов (редко используется)
- `/admin/deepseek-balance` — DeepSeek (редко)
- `/admin/brain` — Второй мозг (редко)
- `/trading/wizard` — визард (используется не каждый раз)
- `/trading/run/*` — детали прогона

**Не выносить:** `/` (главная), `/trading` (список стратегий), `/login`, `/register`.

**🔥 Прирост:** initial bundle уменьшится с 2-3MB до ~1-1.5MB.

### 2.2 Lazy loading изображений

**⏱ 1 час · 🟡 Medium · Эффект: первая загрузка на 200-500ms быстрее**

**📁 `pubspec.yaml`:**
```yaml
dependencies:
  cached_network_image: ^3.3.0
```

**Что делаем:**
1. Все `Image.network()` → `CachedNetworkImage()` с placeholder
2. Все иконки SVG/Font из ассетов проверить — не грузятся ли лишние
3. Шрифты `google_fonts` — кэшировать:

```dart
// Инициализация при старте
await GoogleFonts.prefetchFonts([GoogleFonts.inter()]);
```

### 2.3 Keep-alive + кэш для API (Dio)

**⏱ 30 мин · 🟡 Medium · Эффект: 50-90% меньше latency на повторных запросах**

**📁 `pubspec.yaml`:**
```yaml
dependencies:
  dio_cache_interceptor: ^3.5.0
  dio_cache_interceptor_provider: ^1.0.0
```

**📁 В `DioClient`:**
```dart
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:dio_cache_interceptor_provider/dio_cache_interceptor_provider.dart';

class DioClient {
  late final Dio dio;

  DioClient() {
    dio = Dio(BaseOptions(
      baseUrl: '/api/v1',
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 10),
      persistentConnection: true, // keep-alive
    ));

    // Кэш для GET-запросов
    dio.interceptors.add(DioCacheInterceptor(
      options: CacheOptions(
        store: MemCacheStore(),
        policy: CachePolicy.refresh,
        maxStale: const Duration(minutes: 5),
        priority: CachePriority.normal,
      ),
    ));
  }
}
```

### 2.4 Font subsetting — обрезать шрифты

**⏱ 30 мин · 🟢 Nice · Эффект: -100-300KB**

В `pubspec.yaml` шрифты грузятся целиком (латиница + кириллица + символы). Можно обрезать:

```yaml
fonts:
  - family: Inter
    fonts:
      - asset: assets/fonts/inter/Inter-Regular.ttf
        weight: 400
      # Только нужные weight — не грузить Thin, ExtraLight, Black
```

**Или использовать `google_fonts` с `textFonts`:**
```dart
await GoogleFonts.prefetchFonts(
  [GoogleFonts.getFont('Inter', textFonts: ['Regular', 'Medium', 'SemiBold', 'Bold'])],
);
```

---

## 🔷 Фаза 3: Глубокая оптимизация — неделя

### 3.1 Анализ бандла — что жрёт размер

**⏱ 1 час · 🟡 Medium**

```bash
# Собрать с source maps
flutter build web --release --source-maps --web-renderer html

# Установить инструмент анализа
dart pub global activate dart2js_info

# Анализировать размер функций/пакетов
dart2js_info info build/web/main.dart.js.info
```

**Что ищем:**
- Крупные функции > 10KB
- Неиспользуемые пакеты
- Дублирование кода

### 3.2 WASM режим

**⏱ 1 час · 🟢 Nice · Эффект: 2-5x быстрее выполнение, но старт может быть медленнее**

```bash
flutter build web --wasm
```

**Требования:** Chrome 119+, Flutter 3.22+
**Подводный камень:** WASM-бандл грузится дольше, но выполняется быстрее. Для нашего случая (навигация по страницам) — может дать обратный эффект.

### 3.3 Critical CSS inlining

**⏱ 2 часа · 🟢 Nice**

Стили для первого экрана (above-the-fold) встроить прямо в `index.html` вместо загрузки отдельным файлом:

```html
<style>
  /* Critical: фон, шрифт, логотип, кнопки Войти/Регистрация */
  body { background: #0B0E11; }
  .splash-logo { ... }
</style>
```

### 3.4 Compression (gzip/brotli)

**⏱ 1 час · 🟡 Medium · Эффект: -60-80% размера при передаче**

**Проверить:** наш proxy_server.py на `:8790` уже поддерживает gzip (есть в коде). Но нужно убедиться, что:
```python
# Проверить proxy_server.py:
# 1. gzip включён для HTML/CSS/JS
if suffix in GZIP_TYPES and "gzip" in accept_gzip and len(content) > 1400:
    compressed = gzip.compress(content, compresslevel=6)
```

**Cloudflare:** автоматически brotli-сжимает, если прокси отдаёт без сжатия. Наш прокси сам сжимает — может конфликтовать. **Тест:** отключить gzip в прокси, довериться Cloudflare.

### 3.5 Tree-shaking — проверить пакеты

**⏱ 30 мин · 🟡 Medium**

```bash
# Смотрим что попало в бандл
grep -oP '"lib/[^"]+' build/web/main.dart.js | sort -u | head -50
```

**Проверить:**
- `MaterialIcons` — в бандле ~1.6MB (tree-shaking должен обрезать до ~7KB)
- Неиспользуемые пакеты в `pubspec.yaml`

---

## 📋 Резюме — быстрые победы vs глубокие

| # | Действие | Время | Эффект | Сложность |
|---|----------|-------|--------|-----------|
| ✅ | HTML renderer вместо CanvasKit | 5 мин | -30-50% FCP | 🔴 High |
| ✅ | Native splash screen | 30 мин | Мгновенный отклик | 🟡 Medium |
| ✅ | Preload критических API | 15 мин | -100-200ms | 🟡 Medium |
| ✅ | Keep-alive + кэш Dio | 30 мин | -50-90% повторов | 🟡 Medium |
| ⏳ | Deferred imports | 2-3 ч | -30-60% bundle | 🔴 High |
| ⏳ | Workbox service worker | 1 ч | 0ms после 1-й загрузки | 🔴 High |
| ⏳ | Lazy loading изображений | 1 ч | -200-500ms | 🟡 Medium |
| ⏳ | Font subsetting | 30 мин | -100-300KB | 🟢 Nice |
| 🧪 | WASM | 1 ч | 2-5xexec, но медл. старт | 🟢 Nice |
| 🧪 | Analysis бандла | 1 ч | Выявить узкие места | 🟡 Medium |

---

## 🚀 Рекомендуемый порядок

```
День 1:
  1. HTML renderer — 5 мин         ← сразу видно
  2. Native splash — 30 мин        ← сразу видно
  3. Preload API — 15 мин          ← мелко

День 2:
  4. Workbox SW — 1 час            ← перезагрузки мгновенны
  5. Keep-alive Dio — 30 мин       ← быстрее API

День 3-4:
  6. Deferred imports — 2-3 часа   ← главный прирост
  7. Lazy loading — 1 час

По мере возможности:
  8. Font subsetting — 30 мин
  9. Анализ бандла — 1 час
  10. WASM — тестировать
```

---

## 🔍 Шпаргалка по командам

```bash
# Сборка
flutter build web --release --web-renderer html
flutter build web --release --web-renderer canvaskit
flutter build web --wasm
flutter build web --release --source-maps

# Анализ
dart run flutter_native_splash:create
flutter clean && flutter pub get

# Deferred (ручная работа)
# В Dart: import '...' deferred as Name;
# Вызов: await Name.loadLibrary();

# Размер
ls -lh build/web/main.dart.js
du -sh build/web/

# Precache manifest (генерация после сборки)
python scripts/generate_sw_manifest.py
```
