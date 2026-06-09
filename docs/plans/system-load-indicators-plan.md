# 📋 План: Индикаторы загрузки системы на странице трейдинга

> **Цель:** Добавить 3 горизонтальных индикатора загрузки (CPU, RAM, API) между блоком выбора режима и табами на странице трейдинга. Данные с бэкенда через psutil + scheduler.

---

## Архитектура

```mermaid
flowchart TD
    subgraph "Страница трейдинга (TradingPage)"
        Header[Header: Торговые стратегии]
        ModeSelector[Блок выбора режима]
        LoadIndicators[3 индикатора загрузки]    ← НОВОЕ
        PillTabs[Pill Tabs: Активные / История]
    end

    subgraph "Бэкенд (новый endpoint)"
        API[/api/v1/system/load] 
        --> CPU[psutil.cpu_percent × 0.85]
        --> RAM[psutil.virtual_memory.used / 10GB]
        --> APIusage[scheduler активные engine / лимиты]
    end

    subgraph "Обновление"
        Timer[Timer.periodic 5s] -->|GET /system/load| API
        API -->|response| setState
    end
```

### Цветовая схема индикаторов (из design skill — Binance trading palette)

| Зона | Цвет | Hex | Диапазон |
|------|------|-----|----------|
| 🟢 Норма | `--success` | `#0ECB81` | 0-60% |
| 🟡 Внимание | `--warning` | `#F0B90B` | 60-80% |
| 🔴 Опасно | `--destructive` | `#F6465D` | 80-100% |

### Предупреждение

При достижении любого из параметров >80% — отображается текст под индикаторами:
> ⚠️ Высокая загрузка CPU (82%). Возможны задержки при запуске новых стратегий.

---

## 🔴 Фаза 1 — Бэкенд: API endpoint /api/v1/system/load

**Файлы:**
- Создать: `backend/app/api/v1/system.py`
- Модифицировать: `backend/app/main.py` — добавить роутер
- Создать: `backend/app/schemas/system.py`
- Установить: `pip install psutil` (скорее всего уже есть)

**Что:** Новый endpoint, который возвращает CPU%, RAM%, API usage.

### Schemas:

```python
class SystemLoadResponse(BaseModel):
    cpu_percent: float          # 0-100, уже скорректировано на 0.85
    ram_gb: float               # 0-10, текущее использование в GB
    api_usage_percent: float    # 0-100, сколько WS/REST от лимита
    active_ob_runs: int
    active_trading_runs: int
    warnings: list[str]         # список предупреждений
```

### Endpoint:

```python
@router.get("/system/load", response_model=SystemLoadResponse)
async def system_load():
    # CPU: 85% от реальной загрузки (запас для системы)
    import psutil
    raw_cpu = psutil.cpu_percent(interval=None)
    cpu_percent = round(raw_cpu * 0.85, 1)

    # RAM: текущее использование, шкала 0-10GB
    mem = psutil.virtual_memory()
    ram_gb = round(mem.used / (1024**3), 2)

    # API: считаем активные engine
    from app.services.trading.scheduler import scheduler
    active_ob = len([e for e in scheduler._engines if ...])  
    # или через scheduler.get_active_ob_count()

    # Лимиты Binance: 5 WS соединений, ~1200 REST weight/min
    # Один engine = 1 WS. Макс 5 = 100%
    # WS лимит = active_ob / 5 * 100
    active_ob = scheduler.get_active_ob_count()
    active_trading = scheduler.get_active_run_count()
    total_active = active_ob + active_trading
    max_ws = 5
    api_usage_percent = round(total_active / max_ws * 100, 1)

    # Предупреждения
    warnings = []
    if cpu_percent > 80:
        warnings.append(f"Высокая загрузка CPU ({cpu_percent}%). Возможны задержки.")
    if ram_gb > 8:
        warnings.append(f"Использовано {ram_gb:.1f}GB RAM. Закройте неиспользуемые приложения.")
    if api_usage_percent > 80:
        warnings.append(f"Достигнут лимит API ({api_usage_percent}%). Новые запуски могут быть заблокированы.")

    return SystemLoadResponse(
        cpu_percent=cpu_percent,
        ram_gb=ram_gb,
        api_usage_percent=api_usage_percent,
        active_ob_runs=active_ob,
        active_trading_runs=active_trading,
        warnings=warnings,
    )
```

### Добавить методы в scheduler:

```python
# В scheduler.py
def get_active_ob_count(self) -> int:
    """Количество активных OB engine."""
    return len([rid for rid in self._engines if rid in self._tasks 
                and not self._tasks[rid].done()])

def get_active_run_count(self) -> int:
    """Количество активных TradingRun (свечных) engine."""
    return self.get_active_count() - self.get_active_ob_count()
```

**Действия:**
1. Создать `backend/app/schemas/system.py`
2. Создать `backend/app/api/v1/system.py`
3. Добавить роутер в `main.py`
4. Добавить `get_active_ob_count()` в scheduler
5. Проверить `pip list | grep psutil`

---

## 🔴 Фаза 2 — Фронт: модель данных

**Файлы:**
- Создать: `app/lib/features/trading/data/models/system_load.dart`

**Что:** Модель для парсинга ответа API.

```dart
class SystemLoad {
  final double cpuPercent;
  final double ramGb;
  final double apiUsagePercent;
  final int activeObRuns;
  final int activeTradingRuns;
  final List<String> warnings;

  const SystemLoad({...});

  factory SystemLoad.fromJson(Map<String, dynamic> json) {
    return SystemLoad(
      cpuPercent: (json['cpu_percent'] as num).toDouble(),
      ramGb: (json['ram_gb'] as num).toDouble(),
      apiUsagePercent: (json['api_usage_percent'] as num).toDouble(),
      activeObRuns: json['active_ob_runs'] as int,
      activeTradingRuns: json['active_trading_runs'] as int,
      warnings: (json['warnings'] as List?)?.cast<String>() ?? [],
    );
  }
}
```

---

## 🟡 Фаза 3 — Фронт: виджет индикатора загрузки

**Файлы:**
- Создать: `app/lib/features/trading/presentation/widgets/load_indicator_bar.dart`

**Что:** Переиспользуемый виджет горизонтального индикатора с цветовой шкалой.

### Спецификация дизайна (из design skill):

```dart
class LoadIndicatorBar extends StatelessWidget {
  final String label;           // "CPU", "RAM", "API"
  final double value;           // 0-100 (%)
  final String displayValue;    // "42.5%", "6.2/10 GB", "60%"
  final PhosphorIconData icon;  // иконка

  // Цвет прогресса:
  // 0-60%  → PfColors.success   (#0ECB81)
  // 60-80% → PfColors.warning   (#F0B90B) 
  // 80-100% → PfColors.destructive (#F6465D)
}
```

**UI:**
```
┌─────────────────────────────────────────┐
│ 💻 CPU                         42.5%   │  ← Label + иконка слева, значение справа
│ ████████████░░░░░░░░░░░░░░░░░░░░░░░░  │  ← Progress bar (10px высота, скруглённые)
│                                         │
│ 🐏 RAM                        6.2/10 GB│
│ ██████████████████████████████░░░░░░░░  │
│                                         │
│ 🌐 API                         60%     │
│ ████████████████████████████░░░░░░░░░░  │
└─────────────────────────────────────────┘
```

**Цвет прогресса:**
```dart
Color _progressColor(double pct) {
  if (pct >= 80) return PfColors.destructive;  // #F6465D
  if (pct >= 60) return const Color(0xFFF0B90B); // warning yellow
  return PfColors.success;                      // #0ECB81
}
```

**Размеры (из design skill — PfSpacing/PfRadius):**
- Высота контейнера: ~56px (включая лейбл + полоска)
- Полоска: 8px высота, `PfRadius.borderRadiusPill` скругление
- Отступ между полосками: `PfSpacing.sm` (12px)
- Padding карточки: `PfSpacing.md` (16px)

---

## 🟡 Фаза 4 — Фронт: виджет панели загрузки

**Файлы:**
- Создать: `app/lib/features/trading/presentation/widgets/system_load_panel.dart`

**Что:** Собирает 3 `LoadIndicatorBar` в карточку с заголовком и предупреждениями.

```dart
class SystemLoadPanel extends StatelessWidget {
  final SystemLoad load;

  Widget build(BuildContext context) {
    final pc = PfColors.of(context);
    return PfCard(            // ← стандартная карточка из design skill
      padding: EdgeInsets.all(PfSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Заголовок
          Text('Загрузка системы', style: PfTypography.titleSm...),
          SizedBox(height: PfSpacing.sm),
          // 3 индикатора
          LoadIndicatorBar(
            icon: PhosphorIconsFill.cpu,
            label: 'CPU',
            value: load.cpuPercent,
            displayValue: '${load.cpuPercent}%',
          ),
          SizedBox(height: PfSpacing.sm),
          LoadIndicatorBar(
            icon: PhosphorIconsFill.memory,
            label: 'RAM',
            value: (load.ramGb / 10 * 100).clamp(0, 100), // нормализация на шкалу 0-10GB
            displayValue: '${load.ramGb.toStringAsFixed(1)}/10 GB',
          ),
          SizedBox(height: PfSpacing.sm),
          LoadIndicatorBar(
            icon: PhosphorIconsFill.wifiHigh,
            label: 'API',
            value: load.apiUsagePercent,
            displayValue: '${load.apiUsagePercent.toStringAsFixed(0)}%',
          ),
          // Предупреждения (если есть)
          if (load.warnings.isNotEmpty) ...[
            SizedBox(height: PfSpacing.sm),
            ...load.warnings.map((w) => Padding(
              padding: EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  PhosphorIcon(PhosphorIconsFill.warning, size: 14, color: PfColors.warning),
                  SizedBox(width: 6),
                  Expanded(child: Text(w, style: PfTypography.bodySm.copyWith(color: PfColors.warning))),
                ],
              ),
            )),
          ],
        ],
      ),
    );
  }
}
```

---

## 🟢 Фаза 5 — Интеграция в TradingPage

**Файлы:**
- Модифицировать: `app/lib/features/trading/presentation/trading_page.dart`

**Что:** Вставить `SystemLoadPanel` между блоком режимов и табами. Добавить `Timer` для опроса API каждые 5 секунд.

### В состояние страницы:

```dart
SystemLoad? _systemLoad;
Timer? _loadTimer;

@override
void initState() {
  super.initState();
  _fetchSystemLoad();
  _loadTimer = Timer.periodic(const Duration(seconds: 5), (_) => _fetchSystemLoad());
}

@override
void dispose() {
  _loadTimer?.cancel();
  super.dispose();
}

Future<void> _fetchSystemLoad() async {
  try {
    final load = await widget.repository.getSystemLoad();
    if (mounted) setState(() => _systemLoad = load);
  } catch (_) {}
}
```

### В build (после ModeSelector, перед PillTabs, строка 227):

```dart
// Было:
const SizedBox(height: PfSpacing.lg),

// ── Pill Tabs ─────────────────────────────────

// Стало:
// ── System Load Indicators ────────────────────
if (_systemLoad != null)
  Padding(
    padding: const EdgeInsets.symmetric(horizontal: PfSpacing.lg),
    child: SystemLoadPanel(load: _systemLoad!),
  ),
const SizedBox(height: PfSpacing.lg),

// ── Pill Tabs ─────────────────────────────────
```

### Добавить метод в TradingRepository:

```dart
Future<SystemLoad> getSystemLoad() async {
  final response = await _dio.get('/system/load');
  return SystemLoad.fromJson(response.data as Map<String, dynamic>);
}
```

---

## 🔴 Фаза 6 — Логика расчёта API usage

**Файлы:**
- Модифицировать: `backend/app/services/trading/scheduler.py`

**Что:** Разделить подсчёт OB и свечных запусков.

```python
def get_active_ob_count(self) -> int:
    """Количество активных OrderBook engine."""
    count = 0
    for rid, task in self._tasks.items():
        if rid in self._engines and not task.done():
            count += 1
    return count

def get_active_scan_count(self) -> int:
    """Количество активных scan-запусков (сканирование всех пар)."""
    count = 0
    for rid, task in self._tasks.items():
        if rid not in self._engines and not task.done():
            # Проверяем по config — если есть pair_list → это scan
            if rid in self._configs and self._configs[rid].get("pair_list"):
                count += 1
    return count
```

**Расчёт API:**
- Каждый OB engine → 1 WS-соединение к Binance
- Каждый TradingRun → использует REST API
- Binance лимит: 5 WS на IP, 1200 REST weight/min
- Считаем `ws_usage = active_ob / 5 * 100`
- REST считаем условно: каждый TradingRun ~10-20 weight/min
- Итоговый API usage = max(ws_usage, rest_usage), capped at 100

> **Упрощение:** Для MVP считаем `total_active / 5 * 100`, где 5 = макс. WS соединений. REST-лимиты шире (1200 weight/min), и мы до них не доходим раньше, чем до лимита WS.

---

## 🟢 Фаза 7 — Анимация и интервал обновления

**Файлы:**
- Модифицировать: `app/lib/features/trading/presentation/trading_page.dart`

**Что:** Плавное заполнение полоски при обновлении.

```dart
// Использовать AnimatedContainer или TweenAnimationBuilder для плавного изменения ширины

AnimatedContainer(
  duration: const Duration(milliseconds: 800),
  curve: Curves.easeOutCubic,
  width: clamp(value / 100 * parentWidth, 0, parentWidth),
  height: 8,
  decoration: BoxDecoration(
    color: _progressColor(value),
    borderRadius: PfRadius.borderRadiusPill,
  ),
)
```

---

## 🚫 НЕ меняем

- `backend/app/services/trading/orderbook/engine.py` — движок OB не трогаем
- `backend/app/services/trading/orderbook/strategies/*.py` — стратегии
- `app/lib/features/trading/presentation/orderbook_wizard_page.dart` — визард
- `app/lib/features/trading/presentation/orderbook_run_detail_page.dart` — детали OB
- `app/lib/shared/tokens/` — дизайн-токены не трогаем
- `app/lib/core/theme.dart` — тему не трогаем

---

## 📦 Зависимости

| Пакет | Статус | Для чего |
|-------|--------|----------|
| `psutil` | ❓ Нужно проверить | CPU + RAM на бэкенде |
| `dio` | ✅ Уже есть | HTTP-запрос с фронта |
| `phosphor_flutter` | ✅ Уже есть | Иконки CPU, RAM, API |

---

## ⏱ Оценка

| Фаза | Описание | Файлы | Время |
|------|----------|-------|-------|
| 🔴 1 | API endpoint + schemas + scheduler methods | 4 | ~20 мин |
| 🔴 2 | Модель SystemLoad на фронте | 1 | ~5 мин |
| 🟡 3 | Виджет LoadIndicatorBar | 1 | ~10 мин |
| 🟡 4 | Виджет SystemLoadPanel | 1 | ~10 мин |
| 🟢 5 | Интеграция в TradingPage + Timer | 2 | ~15 мин |
| 🔴 6 | Логика расчёта API в scheduler | 1 | ~5 мин |
| 🟢 7 | Анимация | 1 | ~5 мин |
| | **Итого:** | **~11 файлов** | **~1 час 10 мин** |

---

## Скриншот расположения (текстовая схема)

```
┌─────────────────────────────────────────┐
│  Торговые стратегии                      │
├─────────────────────────────────────────┤
│  ┌──────────┐  ┌──────────┐             │
│  │ Свечи    │  │ OrderBook│             │  ← Mode Selector
│  └──────────┘  └──────────┘             │
│                                          │
│  ┌─────────────────────────────────────┐ │
│  │ Загрузка системы                    │ │
│  │ 💻 CPU                    42.5%    │ │  ← SystemLoadPanel
│  │ ████████████░░░░░░░░░░░░░░░░░░░░░  │ │      (НОВОЕ)
│  │ 🐏 RAM                   6.2/10 GB │ │
│  │ █████████████████████░░░░░░░░░░░░░  │ │
│  │ 🌐 API                    60%      │ │
│  │ ████████████████████████░░░░░░░░░░  │ │
│  └─────────────────────────────────────┘ │
│                                          │
│  [Активные] [История]                    │  ← Pill Tabs
│  ┌─────────────────────────────────────┐ │
│  │  Активные запуски                   │ │
│  │  ...                                │ │
└─────────────────────────────────────────┘
```

---

## Ключевые решения

1. **85% CPU** — умножаем реальную загрузку на 0.85, чтобы показать «у нас ещё 15% запаса»
2. **10GB RAM** — на ПК 16GB, показываем как 0-10 (не 0-16) — оставляем 6GB для ОС + браузер
3. **5 WS соединений** = 100% API — лимит Binance на IP
4. **Timer 5 секунд** — баланс между актуальностью и нагрузкой
5. **Не блокируем** — только предупреждение, если >80%
