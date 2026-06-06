     1|
     2|# PLAN: Мониторинг Order Book стратегий — видимость сигналов и отказов
     3|
     4|**Версия:** 1.0  
     5|**Дата:** 2026-06-06  
     6|**Цель:** Сделать видимым, почему OB-стратегии не совершают сделок, добавить счётчики сигналов/отказов, ленту последних событий и индикаторы активности на фронте.
     7|
     8|---
     9|
    10|## 📋 Статус выполнения
    11|
    12|| # | Приоритет | Этап | Статус | Проблемы |
    13||---|-----------|------|--------|----------|
    14|| 1 | 🔴 | Счётчики отказов + Signal History Buffer | ✅ **Выполнен** | Нет |
    15|| 2 | 🟡 | API эндпоинт live-статуса | ✅ **Выполнен** | Нет |
    16|| 3 | 🔵 | Signal метрики в БД | ⏳ Ожидает | — |
    17|| 4 | 🟢 | Фронт: блок активности на RunDetail | ⏳ Ожидает | — |
    18|| 5 | 🟢 | Фронт: лента последних сигналов | ⏳ Ожидает | — |
    19|| 6 | 🟢 | Фронт: индикаторы на TradingPage | ⏳ Ожидает | — |
    20|| 7 | ⚪ | Логирование в файл | ⏳ Ожидает | — |
    21|
    22|---
    23|
    24|## 🔴 Приоритет 1: Счётчики отказов + Signal History Buffer — ВЫПОЛНЕН
    25|
    26|### Что сделано
    27|
    28|**Файлы:**
    29|- `backend/app/services/trading/orderbook/engine.py`
    30|- `backend/app/services/trading/orderbook/strategies/base.py`
    31|- `backend/app/services/trading/orderbook/strategies/imbalance_scalping.py`
    32|- `backend/app/services/trading/orderbook/strategies/spread_capture.py`
    33|- `backend/app/services/trading/orderbook/strategies/order_flow_momentum.py`
    34|
    35|**Изменения:**
    36|
    37|1. **engine.py:**
    38|   - Добавлен `from collections import deque`
    39|   - В `__init__`: `self._signal_history: deque[dict]` (maxlen=100), `self._signal_timestamps: deque[datetime]`
    40|   - `self.metrics` расширен с 8 до 20 ключей (12 новых счётчиков отказов)
    41|   - Добавлен метод `_record_signal()` — запись сигнала в history
    42|   - `_on_snapshot()`: на каждый `return` — инкремент счётчика + `_record_signal()`
    43|   - `signals_per_minute` — скользящее окно за 60 сек
    44|   - `status` property: добавлен `recent_signals` (последние 20)
    45|   - При отказе analyze(): читает `self.strategy._last_rejection`
    46|
    47|2. **base.py (стратегии):**
    48|   - Добавлен `self._last_rejection: str = ""`
    49|   - Добавлен метод `_reject(reason)` — запоминает причину отказа
    50|
    51|3. **Все 3 стратегии:**
    52|   - Каждый `return None` в `analyze()` теперь вызывает `_reject()` с детальным описанием
    53|
    54|**Новые счётчики (12 шт):**
    55|```
    56|signals_rejected, signals_per_minute, cache_not_warm,
    57|global_stop_filtered, pairlock_filtered, has_position_filtered,
    58|rejected_spread, rejected_iceberg, rejected_confirm_ticks,
    59|rejected_no_signal, rejected_gatekeeper, rejected_wallet
    60|```
    61|
    62|**Проверка:**
    63|- `python3 -c "from app.services.trading.orderbook.engine import OrderBookEngine"` — ✅
    64|- `python3 -c "from ...strategies.* import ..."` — ✅
    65|- Все 3 стратегии корректно инициализируются с `_reject()`
    66|
    67|---
    68|
    69|## 📋 Текущая проблема
    70|
    71|```
    72|WS снапшот (каждые 100мс)
    73|    ↓
    74|_on_snapshot() в engine.py
    75|    ├─ Cache не прогрет?     → return 🤫
    76|    ├─ Global stop?           → return 🤫
    77|    ├─ PairLock активен?      → return 🤫
    78|    ├─ Уже есть позиция?      → return 🤫
    79|    ├─ analyze() → None?      → return 🤫🤫🤫
    80|    ├─ confirm_entry() False? → return 🤫
    81|    ├─ stake ≤ 0?             → return 🤫
    82|    └─ ✅ ENTRY (единственный лог)
    83|```
    84|
    85|**Симптом:** Стратегия может получить 10,000+ снапшотов, отфильтровать 99.9% из них, а пользователь видит «0 сделок» и не понимает почему.
    86|
    87|

## 🟡 Приоритет 2: API эндпоинт live-статуса — ВЫПОЛНЕН

### Что сделано

**Файлы:**
- `backend/app/services/trading/scheduler.py`
- `backend/app/schemas/trading.py`
- `backend/app/api/v1/orderbook.py`

**Изменения:**

1. **scheduler.py:**
   - Добавлен `self._engines: Dict[int, Any]` — хранит ссылки на активные OB engine
   - Добавлен `get_engine_status(run_id)` — возвращает `engine.status` или None
   - Engine сохраняется в `_engines` при `start_orderbook_run()`
   - Engine удаляется из `_engines` в `finally` блоке `_run_orderbook_engine()`

2. **schemas/trading.py:**
   - Добавлен `OrderBookStatusResponse` — 9 полей (running, pair, strategy, balance, free_balance, open_trades, metrics, active_locks, recent_signals)

3. **api/v1/orderbook.py:**
   - Импортирован `OrderBookStatusResponse`
   - Добавлен эндпоинт `GET /orderbook/runs/{run_id}/status` — возвращает live-статус engine

**Проверка:**
- `python3 -c "from app.schemas.trading import OrderBookStatusResponse"` — ✅
- `python3 -c "from app.api.v1.orderbook import router"` — ✅
- `scheduler._engines` — ✅
- Route `GET /orderbook/runs/{run_id}/status` зарегистрирован — ✅

---

---
    88|
    89|## 🔴 Приоритет 1: Счётчики отказов + Signal History Buffer (бэкенд)
    90|
    91|### Где меняем
    92|
    93|**Файлы:**
    94|- `backend/app/services/trading/orderbook/engine.py` — основной
    95|- `backend/app/services/trading/orderbook/models.py` — модель `OrderBookSignal` (опционально)
    96|
    97|### Что делаем
    98|
    99|#### 1.1 Расширяем `self.metrics` в `OrderBookEngine.__init__()`
   100|
   101|```python
   102|self.metrics = {
   103|    # Было:
   104|    "signals_generated": 0,
   105|    "trades_opened": 0,
   106|    "trades_closed": 0,
   107|    "total_pnl": 0.0,
   108|    "win_count": 0,
   109|    "loss_count": 0,
   110|    "max_drawdown": 0.0,
   111|    "peak_balance": config.initial_balance,
   112|
   113|    # Новое:
   114|    "signals_rejected": 0,       # Общее кол-во отказов
   115|    "signals_per_minute": 0.0,   # Средняя скорость (за 60с)
   116|    "cache_not_warm": 0,         # 1. Кэш не прогрет
   117|    "global_stop_filtered": 0,   # 2. Global protection сработала
   118|    "pairlock_filtered": 0,      # 3. PairLock активен
   119|    "has_position_filtered": 0,  # 4. Уже в позиции
   120|    "rejected_spread": 0,        # 5a. Спред > max
   121|    "rejected_iceberg": 0,       # 5b. Iceberg
   122|    "rejected_confirm_ticks": 0, # 5c. Не хватило тиков
   123|    "rejected_no_signal": 0,     # 5d. analyze() → None (без явной причины)
   124|    "rejected_gatekeeper": 0,    # 6. confirm_trade_entry → False
   125|    "rejected_wallet": 0,        # 7. Не хватило баланса
   126|
   127|    # Время последнего сигнала (для индикатора «жива ли стратегия»)
   128|    "last_signal_at": None,
   129|    "last_signal_type": None,
   130|    "last_rejection_reason": None,
   131|}
   132|```
   133|
   134|#### 1.2 Вставляем счётчики в `_on_snapshot()`
   135|
   136|Для каждого `return` в `_on_snapshot()`:
   137|
   138|```python
   139|# Было:
   140|if not self.cache.is_warm:
   141|    return
   142|
   143|# Стало:
   144|if not self.cache.is_warm:
   145|    self.metrics["cache_not_warm"] += 1
   146|    self._record_signal(None, "cache_not_warm")
   147|    return
   148|
   149|# Аналогично для:
   150|# - protection.global_stop() → metrics["global_stop_filtered"]
   151|# - pairlock.is_locked()    → metrics["pairlock_filtered"]
   152|# - snap.pair in trades     → metrics["has_position_filtered"]
   153|# - snap.spread_pct > cfg   → metrics["rejected_spread"]
   154|# - is_iceberg()            → metrics["rejected_iceberg"]
   155|# - len(window) < ticks     → metrics["rejected_confirm_ticks"]
   156|# - analyze → None          → metrics["rejected_no_signal"]
   157|# - confirm_entry → False   → metrics["rejected_gatekeeper"]
   158|# - stake ≤ 0               → metrics["rejected_wallet"]
   159|```
   160|
   161|Также считаем `signals_per_minute` — скользящее среднее:
   162|
   163|```python
   164|# В _on_snapshot, в самом начале:
   165|now = datetime.now(timezone.utc)
   166|self._signal_timestamps.append(now)
   167|# Чистим старые (>60с)
   168|cutoff = now - timedelta(seconds=60)
   169|while self._signal_timestamps and self._signal_timestamps[0] < cutoff:
   170|    self._signal_timestamps.popleft()
   171|self.metrics["signals_per_minute"] = len(self._signal_timestamps)
   172|```
   173|
   174|#### 1.3 Добавляем `_record_signal()` и `_signal_history`
   175|
   176|```python
   177|# В __init__:
   178|self._signal_history: deque[dict] = deque(maxlen=100)  # 100 записей
   179|self._signal_timestamps: deque[datetime] = deque()      # для signals_per_minute
   180|
   181|# Новый метод:
   182|def _record_signal(self, signal_type: str | None, status: str, detail: str = ""):
   183|    """Записать событие сигнала в историю.
   184|    
   185|    signal_type: "imbalance_buy", "spread_capture", None (нет сигнала)
   186|    status: "accepted" | "rejected" | "filtered"
   187|    detail: причина отказа
   188|    """
   189|    self._signal_history.append({
   190|        "timestamp": datetime.now(timezone.utc).isoformat(),
   191|        "signal_type": signal_type or "none",
   192|        "status": status,
   193|        "detail": detail,
   194|    })
   195|```
   196|
   197|#### 1.4 Добавляем `_record_signal()` во все точки выхода `_on_snapshot()`
   198|
   199|Где нет signal object — передаём `None`:
   200|```python
   201|self._record_signal(None, "filtered", "cache_not_warm")
   202|self._record_signal(None, "filtered", f"spread={snap.spread_pct:.4f} > {c.max_spread_pct}")
   203|self._record_signal(None, "filtered", "iceberg")
   204|self._record_signal(None, "filtered", f"confirm_ticks={len(window)}/{c.confirmation_ticks}")
   205|self._record_signal(None, "filtered", "pairlock")
   206|self._record_signal(None, "filtered", "has_position")
   207|self._record_signal(None, "filtered", "global_stop")
   208|self._record_signal(None, "filtered", "gatekeeper")
   209|self._record_signal(None, "filtered", "wallet")
   210|```
   211|
   212|Где есть signal — передаём его тип:
   213|```python
   214|self._record_signal(signal.entry_tag, "accepted", signal.reason)
   215|```
   216|
   217|#### 1.5 Добавляем `logger.debug()` на каждый отказ
   218|
   219|```python
   220|logger.debug(
   221|    "[OBEngine] REJECT %s | %s | conf=%d snap=%d",
   222|    snap.pair, reason, c.confirmation_ticks, len(window)
   223|)
   224|```
   225|
   226|#### 1.6 Расширяем `status` property
   227|
   228|```python
   229|@property
   230|def status(self) -> dict:
   231|    return {
   232|        # ...было...
   233|        "metrics": {k: round(v, 2) if isinstance(v, float) else v for k, v in self.metrics.items()},
   234|        "active_locks": self.pairlock.active_locks,
   235|        # НОВОЕ:
   236|        "recent_signals": list(self._signal_history)[-20:],  # последние 20
   237|        "signals_per_minute": self.metrics["signals_per_minute"],
   238|    }
   239|```
   240|
   241|### Проверка после этапа
   242|
   243|1. `cd backend && python -c "from app.services.trading.orderbook.engine import OrderBookEngine; print('OK')"` — импорт без ошибок
   244|2. `pytest tests/ -x -k orderbook` — тесты не сломались (если есть)
   245|3. Проверить что `_signal_timestamps` не имеет race condition (использует `async with self._lock`)
   246|
   247|### Зависимость с фронтом
   248|
   249|На этом этапе данные только живут в памяти engine. Фронт их не видит — это нормально. Начинаем наполнять данные.
   250|
   251|---
   252|
   253|## 🟡 Приоритет 2: API эндпоинт live-статуса (бэкенд)
   254|
   255|### Где меняем
   256|
   257|**Файлы:**
   258|- `backend/app/api/v1/orderbook.py` — новый эндпоинт
   259|- `backend/app/schemas/trading.py` — новая Pydantic-схема
   260|- `backend/app/services/trading/scheduler.py` — чтобы достать engine по run_id
   261|
   262|### Что делаем
   263|
   264|#### 2.1 Добавляем метод в scheduler для доступа к engine
   265|
   266|```python
   267|# В scheduler.py:
   268|def get_engine_status(self, run_id: int) -> dict | None:
   269|    """Получить live-статус engine по run_id."""
   270|    engine = self._engines.get(run_id)
   271|    if engine is None:
   272|        return None
   273|    return engine.status
   274|```
   275|
   276|Добавить `_engines: dict[int, OrderBookEngine]` в `TradingScheduler.__init__()`:
   277|```python
   278|self._engines: dict[int, OrderBookEngine] = {}
   279|```
   280|
   281|Сохранять engine при старте:
   282|```python
   283|# В start_orderbook_run():
   284|engine = OrderBookEngine(ob_config)
   285|self._engines[run_id] = engine  # ← НОВОЕ
   286|task = asyncio.create_task(...)
   287|```
   288|
   289|Удалять при завершении:
   290|```python
   291|# В _run_orderbook_engine(), в finally:
   292|self._engines.pop(run_id, None)
   293|```
   294|
   295|#### 2.2 Pydantic-схема для статуса
   296|
   297|```python
   298|# В schemas/trading.py:
   299|class OrderBookStatusResponse(BaseModel):
   300|    running: bool
   301|    pair: str
   302|    strategy: str
   303|    balance: float
   304|    signals_per_minute: float
   305|    metrics: dict
   306|    open_trades: dict
   307|    active_locks: list
   308|    recent_signals: list[dict]  # последние 20
   309|```
   310|
   311|#### 2.3 Новый эндпоинт
   312|
   313|```python
   314|@router.get("/runs/{run_id}/status", response_model=OrderBookStatusResponse)
   315|async def get_orderbook_run_status(
   316|    run_id: int,
   317|    current_user: User = Depends(get_current_user),
   318|    session: AsyncSession = Depends(get_session),
   319|) -> OrderBookStatusResponse:
   320|    # Проверить что run принадлежит пользователю
   321|    stmt = select(DBOrderBookRun).where(
   322|        DBOrderBookRun.id == run_id,
   323|        DBOrderBookRun.user_id == current_user.id,
   324|    )
   325|    result = await session.execute(stmt)
   326|    db_run = result.scalar_one_or_none()
   327|    if not db_run:
   328|        raise HTTPException(status_code=404, detail="Run not found")
   329|
   330|    status = scheduler.get_engine_status(run_id)
   331|    if status is None:
   332|        raise HTTPException(status_code=404, detail="Engine not running")
   333|
   334|    return OrderBookStatusResponse(**status)
   335|```
   336|
   337|### Проверка после этапа
   338|
   339|1. Запустить бэкенд: `cd backend && PYTHONPATH=$PWD uvicorn app.main:app`
   340|2. Создать тестовый OB-запуск
   341|3. Вызвать `curl http://localhost:8000/api/v1/orderbook/runs/{id}/status`
   342|4. Проверить что возвращается полный статус с метриками
   343|5. `dart analyze` — импорт схемы не сломал фронт (опционально)
   344|
   345|### Как работает с фронтом
   346|
   347|Фронт будет дёргать `GET /runs/{id}/status` раз в 2-3 секунды для активных запусков. Получает все метрики + recent_signals.
   348|
   349|---
   350|
   351|## 🔵 Приоритет 3: Signal History Buffer + метрики в БД (live-сохранение)
   352|
   353|### Где меняем
   354|
   355|**Файлы:**
   356|- `backend/app/models/trading.py` — новые поля OrderBookRun
   357|- `backend/app/services/trading/scheduler.py` — расширить `_save_ob_live_status()`
   358|- `backend/app/schemas/trading.py` — расширить OrderBookRunResponse
   359|
   360|### Что делаем
   361|
   362|#### 3.1 Новые поля в OrderBookRun
   363|
   364|```python
   365|class OrderBookRun(Base):
   366|    # ...существующие поля...
   367|    
   368|    # НОВОЕ: live-метрики (обновляются каждые 3 сек)
   369|    signals_total = Column(Integer, nullable=True, default=0)
   370|    signals_rejected = Column(Integer, nullable=True, default=0)
   371|    signals_per_minute = Column(Float, nullable=True, default=0.0)
   372|    
   373|    # НОВОЕ: последний сигнал (для визуала)
   374|    last_signal_at = Column(DateTime(timezone=True), nullable=True)
   375|    last_signal_type = Column(String(50), nullable=True)
   376|    last_rejection_reason = Column(String(200), nullable=True)
   377|    
   378|    # НОВОЕ: сигнальное резюме (JSON-строка)
   379|    signal_summary_json = Column(Text, nullable=True)
   380|```
   381|
   382|#### 3.2 Расширяем `_save_ob_live_status()`
   383|
   384|```python
   385|# В scheduler.py _save_ob_live_status():
   386|# Взять метрики из engine
   387|metrics = getattr(engine, "metrics", {})
   388|signals_generated = metrics.get("signals_generated", 0)
   389|
   390|# Сигнальное резюме (топ-5 причин отказов)
   391|rejection_breakdown = {
   392|    k: v for k, v in metrics.items()
   393|    if k.startswith("rejected_") or k.endswith("_filtered")
   394|}
   395|
   396|values = {
   397|    "current_balance": current_balance,
   398|    "open_trade_json": json.dumps(open_trade) if open_trade else None,
   399|    # НОВОЕ:
   400|    "signals_total": signals_generated,
   401|    "signals_rejected": metrics.get("signals_rejected", 0),
   402|    "signals_per_minute": metrics.get("signals_per_minute", 0.0),
   403|    "last_signal_at": metrics.get("last_signal_at"),
   404|    "last_signal_type": metrics.get("last_signal_type"),
   405|    "last_rejection_reason": metrics.get("last_rejection_reason"),
   406|    "signal_summary_json": json.dumps(rejection_breakdown),
   407|}
   408|```
   409|
   410|#### 3.3 Нужна миграция
   411|
   412|```bash
   413|cd backend && PYTHONPATH=$PWD alembic revision --autogenerate -m "add signal metrics to ob runs"
   414|# Проверить сгенерированный файл
   415|cd backend && PYTHONPATH=$PWD alembic upgrade head
   416|```
   417|
   418|### Проверка после этапа
   419|
   420|1. Миграция выполняется без ошибок
   421|2. При live-запуске — поля `signals_total`, `signals_rejected` заполняются
   422|3. `curl .../orderbook/runs/{id}` — возвращает новые поля
   423|
   424|### Как работает с фронтом
   425|
   426|Фронт получает метрики через существующий `GET /runs/{id}` (который дёргается раз в 5 сек). Без нового эндпоинта — данные уже в ответе.
   427|
   428|---
   429|
   430|## 🟢 Приоритет 4: Фронт — блок активности сигналов на RunDetailPage
   431|
   432|### Где меняем
   433|
   434|**Файл:**
   435|- `app/lib/features/trading/presentation/orderbook_run_detail_page.dart`
   436|- `app/lib/features/trading/data/trading_repository.dart` — новый метод
   437|
   438|### Что делаем
   439|
   440|#### 4.1 Новый метод в репозитории
   441|
   442|```dart
   443|Future<Map<String, dynamic>> getOrderBookRunStatus(int runId) async {
   444|  final response = await client.get('/api/v1/orderbook/runs/$runId/status');
   445|  return response.data as Map<String, dynamic>;
   446|}
   447|```
   448|
   449|#### 4.2 Новый блок «Активность сигналов» на RunDetailPage
   450|
   451|Расположить **после баланса, перед настройками** (или наоборот — смотрим).
   452|
   453|```dart
   454|Widget _buildSignalActivity(PfColors pc) {
   455|  // Если запуск не running — не показываем
   456|  if (_run?['status'] != 'running') return const SizedBox();
   457|  
   458|  // Берём из _run (сохраняется в БД) или из _liveStatus (если есть)
   459|  final total = _run?['signals_total'] as int? ?? 0;
   460|  final rejected = _run?['signals_rejected'] as int? ?? 0;
   461|  final spm = (_run?['signals_per_minute'] as num?)?.toDouble() ?? 0;
   462|  
   463|  final accepted = total - rejected;
   464|  final rejectRate = total > 0 ? (rejected / total * 100) : 0.0;
   465|  
   466|  return PfCard(
   467|    child: Column(
   468|      crossAxisAlignment: CrossAxisAlignment.start,
   469|      children: [
   470|        Row(
   471|          children: [
   472|            PhosphorIcon(PhosphorIconsFill.waveform, size: 16, color: pc.foregroundC),
   473|            const SizedBox(width: 8),
   474|            Text('Активность сигналов', style: ...),
   475|            const Spacer(),
   476|            // Индикатор «жива ли стратегия»
   477|            _buildAliveIndicator(spm, pc),
   478|          ],
   479|        ),
   480|        const SizedBox(height: PfSpacing.sm),
   481|        const PfDivider(),
   482|        const SizedBox(height: PfSpacing.sm),
   483|        
   484|        // Большая цифра: всего сигналов
   485|        _bigMetric(pc, '$total', 'сигналов всего'),
   486|        
   487|        // Speed: сигналов/мин
   488|        _speedIndicator(spm, pc, theme),
   489|        
   490|        // Прогресс-бар принято/отсеяно
   491|        _acceptRejectBar(accepted, rejected, pc),
   492|        
   493|        // Разбивка по причинам (из signal_summary)
   494|        if (_run?['signal_summary_json'] != null)
   495|          _rejectionBreakdown(pc, jsonDecode(_run!['signal_summary_json'] as String)),
   496|      ],
   497|    ),
   498|  );
   499|}
   500|```
   501|
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
