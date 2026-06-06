
# PLAN: Мониторинг Order Book стратегий — видимость сигналов и отказов

**Версия:** 1.0  
**Дата:** 2026-06-06  
**Цель:** Сделать видимым, почему OB-стратегии не совершают сделок, добавить счётчики сигналов/отказов, ленту последних событий и индикаторы активности на фронте.

---

## 📋 Статус выполнения

| # | Приоритет | Этап | Статус | Проблемы |
|---|-----------|------|--------|----------|
| 1 | 🔴 | Счётчики отказов + Signal History Buffer | ✅ **Выполнен** | Нет |
| 2 | 🟡 | API эндпоинт live-статуса | ⏳ Ожидает | — |
| 3 | 🔵 | Signal метрики в БД | ⏳ Ожидает | — |
| 4 | 🟢 | Фронт: блок активности на RunDetail | ⏳ Ожидает | — |
| 5 | 🟢 | Фронт: лента последних сигналов | ⏳ Ожидает | — |
| 6 | 🟢 | Фронт: индикаторы на TradingPage | ⏳ Ожидает | — |
| 7 | ⚪ | Логирование в файл | ⏳ Ожидает | — |

---

## 🔴 Приоритет 1: Счётчики отказов + Signal History Buffer — ВЫПОЛНЕН

### Что сделано

**Файлы:**
- `backend/app/services/trading/orderbook/engine.py`
- `backend/app/services/trading/orderbook/strategies/base.py`
- `backend/app/services/trading/orderbook/strategies/imbalance_scalping.py`
- `backend/app/services/trading/orderbook/strategies/spread_capture.py`
- `backend/app/services/trading/orderbook/strategies/order_flow_momentum.py`

**Изменения:**

1. **engine.py:**
   - Добавлен `from collections import deque`
   - В `__init__`: `self._signal_history: deque[dict]` (maxlen=100), `self._signal_timestamps: deque[datetime]`
   - `self.metrics` расширен с 8 до 20 ключей (12 новых счётчиков отказов)
   - Добавлен метод `_record_signal()` — запись сигнала в history
   - `_on_snapshot()`: на каждый `return` — инкремент счётчика + `_record_signal()`
   - `signals_per_minute` — скользящее окно за 60 сек
   - `status` property: добавлен `recent_signals` (последние 20)
   - При отказе analyze(): читает `self.strategy._last_rejection`

2. **base.py (стратегии):**
   - Добавлен `self._last_rejection: str = ""`
   - Добавлен метод `_reject(reason)` — запоминает причину отказа

3. **Все 3 стратегии:**
   - Каждый `return None` в `analyze()` теперь вызывает `_reject()` с детальным описанием

**Новые счётчики (12 шт):**
```
signals_rejected, signals_per_minute, cache_not_warm,
global_stop_filtered, pairlock_filtered, has_position_filtered,
rejected_spread, rejected_iceberg, rejected_confirm_ticks,
rejected_no_signal, rejected_gatekeeper, rejected_wallet
```

**Проверка:**
- `python3 -c "from app.services.trading.orderbook.engine import OrderBookEngine"` — ✅
- `python3 -c "from ...strategies.* import ..."` — ✅
- Все 3 стратегии корректно инициализируются с `_reject()`

---

## 📋 Текущая проблема

```
WS снапшот (каждые 100мс)
    ↓
_on_snapshot() в engine.py
    ├─ Cache не прогрет?     → return 🤫
    ├─ Global stop?           → return 🤫
    ├─ PairLock активен?      → return 🤫
    ├─ Уже есть позиция?      → return 🤫
    ├─ analyze() → None?      → return 🤫🤫🤫
    ├─ confirm_entry() False? → return 🤫
    ├─ stake ≤ 0?             → return 🤫
    └─ ✅ ENTRY (единственный лог)
```

**Симптом:** Стратегия может получить 10,000+ снапшотов, отфильтровать 99.9% из них, а пользователь видит «0 сделок» и не понимает почему.

---

## 🔴 Приоритет 1: Счётчики отказов + Signal History Buffer (бэкенд)

### Где меняем

**Файлы:**
- `backend/app/services/trading/orderbook/engine.py` — основной
- `backend/app/services/trading/orderbook/models.py` — модель `OrderBookSignal` (опционально)

### Что делаем

#### 1.1 Расширяем `self.metrics` в `OrderBookEngine.__init__()`

```python
self.metrics = {
    # Было:
    "signals_generated": 0,
    "trades_opened": 0,
    "trades_closed": 0,
    "total_pnl": 0.0,
    "win_count": 0,
    "loss_count": 0,
    "max_drawdown": 0.0,
    "peak_balance": config.initial_balance,

    # Новое:
    "signals_rejected": 0,       # Общее кол-во отказов
    "signals_per_minute": 0.0,   # Средняя скорость (за 60с)
    "cache_not_warm": 0,         # 1. Кэш не прогрет
    "global_stop_filtered": 0,   # 2. Global protection сработала
    "pairlock_filtered": 0,      # 3. PairLock активен
    "has_position_filtered": 0,  # 4. Уже в позиции
    "rejected_spread": 0,        # 5a. Спред > max
    "rejected_iceberg": 0,       # 5b. Iceberg
    "rejected_confirm_ticks": 0, # 5c. Не хватило тиков
    "rejected_no_signal": 0,     # 5d. analyze() → None (без явной причины)
    "rejected_gatekeeper": 0,    # 6. confirm_trade_entry → False
    "rejected_wallet": 0,        # 7. Не хватило баланса

    # Время последнего сигнала (для индикатора «жива ли стратегия»)
    "last_signal_at": None,
    "last_signal_type": None,
    "last_rejection_reason": None,
}
```

#### 1.2 Вставляем счётчики в `_on_snapshot()`

Для каждого `return` в `_on_snapshot()`:

```python
# Было:
if not self.cache.is_warm:
    return

# Стало:
if not self.cache.is_warm:
    self.metrics["cache_not_warm"] += 1
    self._record_signal(None, "cache_not_warm")
    return

# Аналогично для:
# - protection.global_stop() → metrics["global_stop_filtered"]
# - pairlock.is_locked()    → metrics["pairlock_filtered"]
# - snap.pair in trades     → metrics["has_position_filtered"]
# - snap.spread_pct > cfg   → metrics["rejected_spread"]
# - is_iceberg()            → metrics["rejected_iceberg"]
# - len(window) < ticks     → metrics["rejected_confirm_ticks"]
# - analyze → None          → metrics["rejected_no_signal"]
# - confirm_entry → False   → metrics["rejected_gatekeeper"]
# - stake ≤ 0               → metrics["rejected_wallet"]
```

Также считаем `signals_per_minute` — скользящее среднее:

```python
# В _on_snapshot, в самом начале:
now = datetime.now(timezone.utc)
self._signal_timestamps.append(now)
# Чистим старые (>60с)
cutoff = now - timedelta(seconds=60)
while self._signal_timestamps and self._signal_timestamps[0] < cutoff:
    self._signal_timestamps.popleft()
self.metrics["signals_per_minute"] = len(self._signal_timestamps)
```

#### 1.3 Добавляем `_record_signal()` и `_signal_history`

```python
# В __init__:
self._signal_history: deque[dict] = deque(maxlen=100)  # 100 записей
self._signal_timestamps: deque[datetime] = deque()      # для signals_per_minute

# Новый метод:
def _record_signal(self, signal_type: str | None, status: str, detail: str = ""):
    """Записать событие сигнала в историю.
    
    signal_type: "imbalance_buy", "spread_capture", None (нет сигнала)
    status: "accepted" | "rejected" | "filtered"
    detail: причина отказа
    """
    self._signal_history.append({
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "signal_type": signal_type or "none",
        "status": status,
        "detail": detail,
    })
```

#### 1.4 Добавляем `_record_signal()` во все точки выхода `_on_snapshot()`

Где нет signal object — передаём `None`:
```python
self._record_signal(None, "filtered", "cache_not_warm")
self._record_signal(None, "filtered", f"spread={snap.spread_pct:.4f} > {c.max_spread_pct}")
self._record_signal(None, "filtered", "iceberg")
self._record_signal(None, "filtered", f"confirm_ticks={len(window)}/{c.confirmation_ticks}")
self._record_signal(None, "filtered", "pairlock")
self._record_signal(None, "filtered", "has_position")
self._record_signal(None, "filtered", "global_stop")
self._record_signal(None, "filtered", "gatekeeper")
self._record_signal(None, "filtered", "wallet")
```

Где есть signal — передаём его тип:
```python
self._record_signal(signal.entry_tag, "accepted", signal.reason)
```

#### 1.5 Добавляем `logger.debug()` на каждый отказ

```python
logger.debug(
    "[OBEngine] REJECT %s | %s | conf=%d snap=%d",
    snap.pair, reason, c.confirmation_ticks, len(window)
)
```

#### 1.6 Расширяем `status` property

```python
@property
def status(self) -> dict:
    return {
        # ...было...
        "metrics": {k: round(v, 2) if isinstance(v, float) else v for k, v in self.metrics.items()},
        "active_locks": self.pairlock.active_locks,
        # НОВОЕ:
        "recent_signals": list(self._signal_history)[-20:],  # последние 20
        "signals_per_minute": self.metrics["signals_per_minute"],
    }
```

### Проверка после этапа

1. `cd backend && python -c "from app.services.trading.orderbook.engine import OrderBookEngine; print('OK')"` — импорт без ошибок
2. `pytest tests/ -x -k orderbook` — тесты не сломались (если есть)
3. Проверить что `_signal_timestamps` не имеет race condition (использует `async with self._lock`)

### Зависимость с фронтом

На этом этапе данные только живут в памяти engine. Фронт их не видит — это нормально. Начинаем наполнять данные.

---

## 🟡 Приоритет 2: API эндпоинт live-статуса (бэкенд)

### Где меняем

**Файлы:**
- `backend/app/api/v1/orderbook.py` — новый эндпоинт
- `backend/app/schemas/trading.py` — новая Pydantic-схема
- `backend/app/services/trading/scheduler.py` — чтобы достать engine по run_id

### Что делаем

#### 2.1 Добавляем метод в scheduler для доступа к engine

```python
# В scheduler.py:
def get_engine_status(self, run_id: int) -> dict | None:
    """Получить live-статус engine по run_id."""
    engine = self._engines.get(run_id)
    if engine is None:
        return None
    return engine.status
```

Добавить `_engines: dict[int, OrderBookEngine]` в `TradingScheduler.__init__()`:
```python
self._engines: dict[int, OrderBookEngine] = {}
```

Сохранять engine при старте:
```python
# В start_orderbook_run():
engine = OrderBookEngine(ob_config)
self._engines[run_id] = engine  # ← НОВОЕ
task = asyncio.create_task(...)
```

Удалять при завершении:
```python
# В _run_orderbook_engine(), в finally:
self._engines.pop(run_id, None)
```

#### 2.2 Pydantic-схема для статуса

```python
# В schemas/trading.py:
class OrderBookStatusResponse(BaseModel):
    running: bool
    pair: str
    strategy: str
    balance: float
    signals_per_minute: float
    metrics: dict
    open_trades: dict
    active_locks: list
    recent_signals: list[dict]  # последние 20
```

#### 2.3 Новый эндпоинт

```python
@router.get("/runs/{run_id}/status", response_model=OrderBookStatusResponse)
async def get_orderbook_run_status(
    run_id: int,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> OrderBookStatusResponse:
    # Проверить что run принадлежит пользователю
    stmt = select(DBOrderBookRun).where(
        DBOrderBookRun.id == run_id,
        DBOrderBookRun.user_id == current_user.id,
    )
    result = await session.execute(stmt)
    db_run = result.scalar_one_or_none()
    if not db_run:
        raise HTTPException(status_code=404, detail="Run not found")

    status = scheduler.get_engine_status(run_id)
    if status is None:
        raise HTTPException(status_code=404, detail="Engine not running")

    return OrderBookStatusResponse(**status)
```

### Проверка после этапа

1. Запустить бэкенд: `cd backend && PYTHONPATH=$PWD uvicorn app.main:app`
2. Создать тестовый OB-запуск
3. Вызвать `curl http://localhost:8000/api/v1/orderbook/runs/{id}/status`
4. Проверить что возвращается полный статус с метриками
5. `dart analyze` — импорт схемы не сломал фронт (опционально)

### Как работает с фронтом

Фронт будет дёргать `GET /runs/{id}/status` раз в 2-3 секунды для активных запусков. Получает все метрики + recent_signals.

---

## 🔵 Приоритет 3: Signal History Buffer + метрики в БД (live-сохранение)

### Где меняем

**Файлы:**
- `backend/app/models/trading.py` — новые поля OrderBookRun
- `backend/app/services/trading/scheduler.py` — расширить `_save_ob_live_status()`
- `backend/app/schemas/trading.py` — расширить OrderBookRunResponse

### Что делаем

#### 3.1 Новые поля в OrderBookRun

```python
class OrderBookRun(Base):
    # ...существующие поля...
    
    # НОВОЕ: live-метрики (обновляются каждые 3 сек)
    signals_total = Column(Integer, nullable=True, default=0)
    signals_rejected = Column(Integer, nullable=True, default=0)
    signals_per_minute = Column(Float, nullable=True, default=0.0)
    
    # НОВОЕ: последний сигнал (для визуала)
    last_signal_at = Column(DateTime(timezone=True), nullable=True)
    last_signal_type = Column(String(50), nullable=True)
    last_rejection_reason = Column(String(200), nullable=True)
    
    # НОВОЕ: сигнальное резюме (JSON-строка)
    signal_summary_json = Column(Text, nullable=True)
```

#### 3.2 Расширяем `_save_ob_live_status()`

```python
# В scheduler.py _save_ob_live_status():
# Взять метрики из engine
metrics = getattr(engine, "metrics", {})
signals_generated = metrics.get("signals_generated", 0)

# Сигнальное резюме (топ-5 причин отказов)
rejection_breakdown = {
    k: v for k, v in metrics.items()
    if k.startswith("rejected_") or k.endswith("_filtered")
}

values = {
    "current_balance": current_balance,
    "open_trade_json": json.dumps(open_trade) if open_trade else None,
    # НОВОЕ:
    "signals_total": signals_generated,
    "signals_rejected": metrics.get("signals_rejected", 0),
    "signals_per_minute": metrics.get("signals_per_minute", 0.0),
    "last_signal_at": metrics.get("last_signal_at"),
    "last_signal_type": metrics.get("last_signal_type"),
    "last_rejection_reason": metrics.get("last_rejection_reason"),
    "signal_summary_json": json.dumps(rejection_breakdown),
}
```

#### 3.3 Нужна миграция

```bash
cd backend && PYTHONPATH=$PWD alembic revision --autogenerate -m "add signal metrics to ob runs"
# Проверить сгенерированный файл
cd backend && PYTHONPATH=$PWD alembic upgrade head
```

### Проверка после этапа

1. Миграция выполняется без ошибок
2. При live-запуске — поля `signals_total`, `signals_rejected` заполняются
3. `curl .../orderbook/runs/{id}` — возвращает новые поля

### Как работает с фронтом

Фронт получает метрики через существующий `GET /runs/{id}` (который дёргается раз в 5 сек). Без нового эндпоинта — данные уже в ответе.

---

## 🟢 Приоритет 4: Фронт — блок активности сигналов на RunDetailPage

### Где меняем

**Файл:**
- `app/lib/features/trading/presentation/orderbook_run_detail_page.dart`
- `app/lib/features/trading/data/trading_repository.dart` — новый метод

### Что делаем

#### 4.1 Новый метод в репозитории

```dart
Future<Map<String, dynamic>> getOrderBookRunStatus(int runId) async {
  final response = await client.get('/api/v1/orderbook/runs/$runId/status');
  return response.data as Map<String, dynamic>;
}
```

#### 4.2 Новый блок «Активность сигналов» на RunDetailPage

Расположить **после баланса, перед настройками** (или наоборот — смотрим).

```dart
Widget _buildSignalActivity(PfColors pc) {
  // Если запуск не running — не показываем
  if (_run?['status'] != 'running') return const SizedBox();
  
  // Берём из _run (сохраняется в БД) или из _liveStatus (если есть)
  final total = _run?['signals_total'] as int? ?? 0;
  final rejected = _run?['signals_rejected'] as int? ?? 0;
  final spm = (_run?['signals_per_minute'] as num?)?.toDouble() ?? 0;
  
  final accepted = total - rejected;
  final rejectRate = total > 0 ? (rejected / total * 100) : 0.0;
  
  return PfCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            PhosphorIcon(PhosphorIconsFill.waveform, size: 16, color: pc.foregroundC),
            const SizedBox(width: 8),
            Text('Активность сигналов', style: ...),
            const Spacer(),
            // Индикатор «жива ли стратегия»
            _buildAliveIndicator(spm, pc),
          ],
        ),
        const SizedBox(height: PfSpacing.sm),
        const PfDivider(),
        const SizedBox(height: PfSpacing.sm),
        
        // Большая цифра: всего сигналов
        _bigMetric(pc, '$total', 'сигналов всего'),
        
        // Speed: сигналов/мин
        _speedIndicator(spm, pc, theme),
        
        // Прогресс-бар принято/отсеяно
        _acceptRejectBar(accepted, rejected, pc),
        
        // Разбивка по причинам (из signal_summary)
        if (_run?['signal_summary_json'] != null)
          _rejectionBreakdown(pc, jsonDecode(_run!['signal_summary_json'] as String)),
      ],
    ),
  );
}
```

#### 4.3 Детали виджетов

**`_buildAliveIndicator()`:**
```dart
Widget _buildAliveIndicator(double spm, PfColors pc) {
  if (spm < 1) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(
          color: PfColors.warning, shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: PfColors.warning.withValues(alpha: 0.4), blurRadius: 4)],
        )),
        const SizedBox(width: 6),
        Text('Нет сигналов', style: PfTypography.caption.copyWith(color: PfColors.warning)),
      ],
    );
  }
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 8, height: 8, decoration: BoxDecoration(
        color: PfColors.success, shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: PfColors.success.withValues(alpha: 0.4), blurRadius: 4)],
      )),
      const SizedBox(width: 6),
      Text('${spm.toStringAsFixed(0)}/мин', style: PfTypography.caption.copyWith(color: PfColors.success)),
    ],
  );
}
```

**`_acceptRejectBar()`:**
```dart
Widget _acceptRejectBar(int accepted, int rejected, PfColors pc) {
  final total = accepted + rejected;
  if (total == 0) return const SizedBox();
  final acceptRatio = accepted / total;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 12),
      ClipRRect(
        borderRadius: PfRadius.borderRadiusPill,
        child: SizedBox(
          height: 8,
          child: Row(
            children: [
              Flexible(
                flex: (acceptRatio * 1000).round(),
                child: Container(color: PfColors.success),
              ),
              if (rejected > 0)
                Flexible(
                  flex: ((1 - acceptRatio) * 1000).round(),
                  child: Container(color: PfColors.destructive.withValues(alpha: 0.5)),
                ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 6),
      Row(
        children: [
          _dotLabel('✅ Принято', accepted.toString(), PfColors.success, pc),
          const SizedBox(width: 16),
          _dotLabel('❌ Отсеяно', rejected.toString(), PfColors.destructive, pc),
        ],
      ),
    ],
  );
}
```

**`_rejectionBreakdown()`:**
```dart
Widget _rejectionBreakdown(PfColors pc, Map<String, dynamic> breakdown) {
  // Фильтруем только счётчики reject/filter
  final items = <MapEntry<String, dynamic>>[];
  for (final entry in breakdown.entries) {
    if ((entry.key.startsWith('rejected_') || entry.key.endsWith('_filtered'))
        && (entry.value is num) && (entry.value as num) > 0) {
      items.add(entry);
    }
  }
  if (items.isEmpty) return const SizedBox();
  
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 12),
      Text('Разбивка по причинам:', style: PfTypography.bodySm.copyWith(color: pc.mutedForegroundC)),
      const SizedBox(height: 6),
      Wrap(
        spacing: 8, runSpacing: 6,
        children: items.map((e) => _reasonChip(e.key, e.value, pc)).toList(),
      ),
    ],
  );
}
```

### 4.4 Обновление по таймеру

Добавить отдельный таймер (рядом с `_pollTimer`) который каждые 3 секунды дёргает `/status` эндпоинт:

```dart
Timer? _signalTimer;

// В initState:
_signalTimer = Timer.periodic(const Duration(seconds: 3), (_) {
  _fetchSignalStatus();
});

// Новый метод:
Future<void> _fetchSignalStatus() async {
  try {
    final status = await widget.repository.getOrderBookRunStatus(widget.runId);
    if (mounted) {
      setState(() {
        // Обновляем _run['signals_total'] и т.д.
      });
    }
  } catch (_) {}
}
```

### Проверка после этапа

1. `cd app && flutter analyze lib/features/trading/presentation/orderbook_run_detail_page.dart`
2. **0 errors**
3. Визуально проверить в браузере: блок активности отображается
4. Проверить что при 0 сигналах — показывает жёлтый индикатор и «Нет сигналов»

### Как работает с бэкендом

- Раз в 3 сек: `GET /api/v1/orderbook/runs/{id}/status` → получает метрики + recent_signals + signals_per_minute
- Отображает всё это в real-time
- При остановке запуска — блок скрывается (показываются итоговые метрики из БД)

---

## 🟢 Приоритет 5: Фронт — лента последних сигналов

### Где меняем

**Файл:**
- `app/lib/features/trading/presentation/orderbook_run_detail_page.dart`

### Что делаем

#### 5.1 Кнопка «Показать последние сигналы» под блоком активности

```dart
PfButton(
  variant: 'ghost',
  size: 'sm',
  label: '📡 Последние сигналы (${recentSignals.length})',
  onPressed: () => _showSignalLog(context),
)
```

#### 5.2 BottomSheet с лентой сигналов

```dart
void _showSignalLog(BuildContext context) {
  final pc = PfColors.of(context);
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (ctx, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: pc.backgroundC,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Handle
            // Заголовок
            // Список: SignalLogTile
          ],
        ),
      ),
    ),
  );
}
```

#### 5.3 SignalLogTile

```dart
Widget _signalLogTile(Map<String, dynamic> signal, PfColors pc) {
  final status = signal['status'] as String? ?? 'filtered';
  final isAccepted = status == 'accepted';
  final signalType = signal['signal_type'] as String? ?? '—';
  final detail = signal['detail'] as String? ?? '';
  final timestamp = signal['timestamp'] as String? ?? '';
  
  return Container(
    padding: ...,
    child: Row(
      children: [
        // Иконка: ✅ / ❌
        PhosphorIcon(
          isAccepted ? PhosphorIconsFill.checkCircle : PhosphorIconsFill.xCircle,
          size: 16,
          color: isAccepted ? PfColors.success : PfColors.destructive.withValues(alpha: 0.6),
        ),
        const SizedBox(width: 8),
        // Тип сигнала + детали
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(signalType, style: ...),
              Text(detail, style: PfTypography.bodySm.copyWith(color: pc.mutedForegroundC)),
            ],
          ),
        ),
        // Время
        Text(_formatSignalTime(timestamp), style: PfTypography.caption.copyWith(color: pc.mutedForegroundC)),
      ],
    ),
  );
}
```

### Проверка после этапа

1. `flutter analyze` — 0 errors
2. Кнопка «Последние сигналы» появляется только когда есть данные
3. BottomSheet скроллится, показывает сигналы от новых к старым
4. ✅ и ❌ иконки цветные

---

## 🟢 Приоритет 6: Фронт — индикаторы активности на TradingPage

### Где меняем

**Файл:**
- `app/lib/features/trading/presentation/trading_page.dart`

### Что делаем

#### 6.1 В `_buildObRunsList()` добавляем метрики в карточки

```dart
// Текущий вид: карточка с названием + парой + статус-бейдж
// + НОВОЕ: индикатор активности

Widget _buildObRunCard(Map<String, dynamic> run, PfColors pc, ThemeData theme) {
  final isActive = run['status'] == 'running';
  final signalsTotal = (run['signals_total'] as num?)?.toInt() ?? 0;
  final signalsRejected = (run['signals_rejected'] as num?)?.toInt() ?? 0;
  final spm = (run['signals_per_minute'] as num?)?.toDouble() ?? 0.0;
  
  return PfCard(
    onTap: () => context.go('/trading/ob-run/${run['id']}'),
    padding: ...,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Заголовок: стратегия + пара + статус
        Row(...),
        const SizedBox(height: 8),
        
        // НОВОЕ: строка активности
        if (isActive) ...[
          _activityRow(spm, signalsTotal, signalsRejected, pc),
          const SizedBox(height: 4),
        ],
        
        // Существующее: stats row
        Row(
          children: [
            _miniStat('PnL', '\$${run['total_pnl'] ?? 0}', ...),
            _miniStat('Сделок', '${run['total_trades'] ?? 0}', ...),
          ],
        ),
      ],
    ),
  );
}
```

#### 6.2 Индикатор активности

```dart
Widget _activityRow(double spm, int total, int rejected, PfColors pc) {
  return Row(
    children: [
      // Точка
      Container(
        width: 8, height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: spm > 0 ? PfColors.success : PfColors.warning,
        ),
      ),
      const SizedBox(width: 6),
      Expanded(
        child: Text(
          spm > 0
              ? '${spm.toStringAsFixed(0)} сигн/мин · $total всего'
              : 'Нет сигналов ($total обработано)',
          style: PfTypography.caption.copyWith(
            color: spm > 0 ? pc.foregroundC : PfColors.warning,
          ),
        ),
      ),
    ],
  );
}
```

#### 6.3 Обновление данных списка каждые 5 секунд

В `_loadObRuns()` уже дёргается список. Если сделать периодический вызов для активных запусков:

```dart
Timer? _obRefreshTimer;

// В initState или при активации таба:
_obRefreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
  if (mounted) _loadObRuns();
});
```

### Проверка после этапа

1. `flutter analyze` — 0 errors
2. В карточках OB-запусков видна строка активности
3. У запусков без сигналов — жёлтая точка с текстом «Нет сигналов»
4. У запусков с сигналами — зелёная точка с `N сигн/мин`

---

## ⚪ Приоритет 7: Логирование сигналов в файл (опционально)

Если нужно сохранять историю сигналов даже после перезапуска сервера.

### Где меняем

**Файл:**
- `backend/app/services/trading/orderbook/engine.py`

### Что делаем

Добавить `logger.debug()` на каждый reject с контекстом:

```python
logger.debug(
    "[OBEngine] %s | pair=%s reason=%s | "
    "metrics: gen=%d rej=%d accept=%d",
    snap.pair,
    reason,
    self.metrics["signals_generated"],
    self.metrics["signals_rejected"],
    self.metrics["trades_opened"],
)
```

В `logging.conf` или `settings.py` — убедиться что debug-логи пишутся в отдельный файл `logs/ob_signals.log` с ротацией.

---

## 📐 Сводная таблица этапов

| # | Приоритет | Название | Бэк/Фронт | Файлов | Оценка |
|---|-----------|----------|-----------|--------|--------|
| 1 | 🔴 | Счётчики отказов + Signal History | Бэк | 1 (engine.py) | ~1ч |
| 2 | 🟡 | API эндпоинт live-статуса | Бэк | 3 (api, schemas, scheduler) | ~1ч |
| 3 | 🔵 | Signal метрики в БД | Бэк | 3 (model, scheduler, migration) | ~1ч |
| 4 | 🟢 | Фронт: блок активности на RunDetail | Фронт | 2 (page, repository) | ~2ч |
| 5 | 🟢 | Фронт: лента последних сигналов | Фронт | 1 (page) | ~1.5ч |
| 6 | 🟢 | Фронт: индикаторы на TradingPage | Фронт | 1 (page) | ~1.5ч |
| 7 | ⚪ | Логирование в файл | Бэк | 2 (engine, logging config) | ~0.5ч |
| | | **Итого** | | **~13 файлов** | **~8.5ч** |

---

## 🔄 Процесс выполнения

**Каждый этап выполняется строго по циклу:**

```
1. Начать этап → отметить в PLANA TODO
2. Внести изменения в код
3. Проверить: dart analyze / flake8 / pytest
4. Если найден баг → исправить до перехода к следующему этапу
5. Запустить сборку (flutter build web)
6. Обновить CHANGELOG.md
7. git add + git commit + git push
8. Отметить этап как выполненный в PLANA TODO
9. Cloudflare purge (если нужен)
```

**После каждого этапа возвращаться к этому документу и отмечать:**
- ✅ Этап выполнен
- ⚠️ Были проблемы (описать)
- ❌ Отложено (причина)
