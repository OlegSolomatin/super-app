     1|     1|
     2|     2|# PLAN: Мониторинг Order Book стратегий — видимость сигналов и отказов
     3|     3|
     4|     4|**Версия:** 1.0  
     5|     5|**Дата:** 2026-06-06  
     6|     6|**Цель:** Сделать видимым, почему OB-стратегии не совершают сделок, добавить счётчики сигналов/отказов, ленту последних событий и индикаторы активности на фронте.
     7|     7|
     8|     8|---
     9|     9|
    10|    10|## 📋 Статус выполнения
    11|    11|
    12|    12|| # | Приоритет | Этап | Статус | Проблемы |
    13|    13||---|-----------|------|--------|----------|
    14|    14|| 1 | 🔴 | Счётчики отказов + Signal History Buffer | ✅ **Выполнен** | Нет |
    15|    15|| 2 | 🟡 | API эндпоинт live-статуса | ✅ **Выполнен** | Нет |
    16|    16|| 3 | 🔵 | Signal метрики в БД | ✅ **Выполнен** | Нет |
    17|    17|| 4 | 🟢 | Фронт: блок активности на RunDetail | ⏳ Ожидает | — |
    18|    18|| 5 | 🟢 | Фронт: лента последних сигналов | ⏳ Ожидает | — |
    19|    19|| 6 | 🟢 | Фронт: индикаторы на TradingPage | ⏳ Ожидает | — |
    20|    20|| 7 | ⚪ | Логирование в файл | ⏳ Ожидает | — |
    21|    21|
    22|    22|---
    23|    23|
    24|    24|## 🔴 Приоритет 1: Счётчики отказов + Signal History Buffer — ВЫПОЛНЕН
    25|    25|
    26|    26|### Что сделано
    27|    27|
    28|    28|**Файлы:**
    29|    29|- `backend/app/services/trading/orderbook/engine.py`
    30|    30|- `backend/app/services/trading/orderbook/strategies/base.py`
    31|    31|- `backend/app/services/trading/orderbook/strategies/imbalance_scalping.py`
    32|    32|- `backend/app/services/trading/orderbook/strategies/spread_capture.py`
    33|    33|- `backend/app/services/trading/orderbook/strategies/order_flow_momentum.py`
    34|    34|
    35|    35|**Изменения:**
    36|    36|
    37|    37|1. **engine.py:**
    38|    38|   - Добавлен `from collections import deque`
    39|    39|   - В `__init__`: `self._signal_history: deque[dict]` (maxlen=100), `self._signal_timestamps: deque[datetime]`
    40|    40|   - `self.metrics` расширен с 8 до 20 ключей (12 новых счётчиков отказов)
    41|    41|   - Добавлен метод `_record_signal()` — запись сигнала в history
    42|    42|   - `_on_snapshot()`: на каждый `return` — инкремент счётчика + `_record_signal()`
    43|    43|   - `signals_per_minute` — скользящее окно за 60 сек
    44|    44|   - `status` property: добавлен `recent_signals` (последние 20)
    45|    45|   - При отказе analyze(): читает `self.strategy._last_rejection`
    46|    46|
    47|    47|2. **base.py (стратегии):**
    48|    48|   - Добавлен `self._last_rejection: str = ""`
    49|    49|   - Добавлен метод `_reject(reason)` — запоминает причину отказа
    50|    50|
    51|    51|3. **Все 3 стратегии:**
    52|    52|   - Каждый `return None` в `analyze()` теперь вызывает `_reject()` с детальным описанием
    53|    53|
    54|    54|**Новые счётчики (12 шт):**
    55|    55|```
    56|    56|signals_rejected, signals_per_minute, cache_not_warm,
    57|    57|global_stop_filtered, pairlock_filtered, has_position_filtered,
    58|    58|rejected_spread, rejected_iceberg, rejected_confirm_ticks,
    59|    59|rejected_no_signal, rejected_gatekeeper, rejected_wallet
    60|    60|```
    61|    61|
    62|    62|**Проверка:**
    63|    63|- `python3 -c "from app.services.trading.orderbook.engine import OrderBookEngine"` — ✅
    64|    64|- `python3 -c "from ...strategies.* import ..."` — ✅
    65|    65|- Все 3 стратегии корректно инициализируются с `_reject()`
    66|    66|
    67|    67|---
    68|    68|
    69|    69|## 📋 Текущая проблема
    70|    70|
    71|    71|```
    72|    72|WS снапшот (каждые 100мс)
    73|    73|    ↓
    74|    74|_on_snapshot() в engine.py
    75|    75|    ├─ Cache не прогрет?     → return 🤫
    76|    76|    ├─ Global stop?           → return 🤫
    77|    77|    ├─ PairLock активен?      → return 🤫
    78|    78|    ├─ Уже есть позиция?      → return 🤫
    79|    79|    ├─ analyze() → None?      → return 🤫🤫🤫
    80|    80|    ├─ confirm_entry() False? → return 🤫
    81|    81|    ├─ stake ≤ 0?             → return 🤫
    82|    82|    └─ ✅ ENTRY (единственный лог)
    83|    83|```
    84|    84|
    85|    85|**Симптом:** Стратегия может получить 10,000+ снапшотов, отфильтровать 99.9% из них, а пользователь видит «0 сделок» и не понимает почему.
    86|    86|
    87|    87|
    88|
    89|## 🟡 Приоритет 2: API эндпоинт live-статуса — ВЫПОЛНЕН
    90|
    91|### Что сделано
    92|
    93|**Файлы:**
    94|- `backend/app/services/trading/scheduler.py`
    95|- `backend/app/schemas/trading.py`
    96|- `backend/app/api/v1/orderbook.py`
    97|
    98|**Изменения:**
    99|
   100|1. **scheduler.py:**
   101|   - Добавлен `self._engines: Dict[int, Any]` — хранит ссылки на активные OB engine
   102|   - Добавлен `get_engine_status(run_id)` — возвращает `engine.status` или None
   103|   - Engine сохраняется в `_engines` при `start_orderbook_run()`
   104|   - Engine удаляется из `_engines` в `finally` блоке `_run_orderbook_engine()`
   105|
   106|2. **schemas/trading.py:**
   107|   - Добавлен `OrderBookStatusResponse` — 9 полей (running, pair, strategy, balance, free_balance, open_trades, metrics, active_locks, recent_signals)
   108|
   109|3. **api/v1/orderbook.py:**
   110|   - Импортирован `OrderBookStatusResponse`
   111|   - Добавлен эндпоинт `GET /orderbook/runs/{run_id}/status` — возвращает live-статус engine
   112|
   113|**Проверка:**
   114|- `python3 -c "from app.schemas.trading import OrderBookStatusResponse"` — ✅
   115|- `python3 -c "from app.api.v1.orderbook import router"` — ✅
   116|- `scheduler._engines` — ✅
   117|- Route `GET /orderbook/runs/{run_id}/status` зарегистрирован — ✅
   118|
   119|---
   120|
   121|---
   122|    88|
   123|    89|## 🔴 Приоритет 1: Счётчики отказов + Signal History Buffer (бэкенд)
   124|    90|
   125|    91|### Где меняем
   126|    92|
   127|    93|**Файлы:**
   128|    94|- `backend/app/services/trading/orderbook/engine.py` — основной
   129|    95|- `backend/app/services/trading/orderbook/models.py` — модель `OrderBookSignal` (опционально)
   130|    96|
   131|    97|### Что делаем
   132|    98|
   133|    99|#### 1.1 Расширяем `self.metrics` в `OrderBookEngine.__init__()`
   134|   100|
   135|   101|```python
   136|   102|self.metrics = {
   137|   103|    # Было:
   138|   104|    "signals_generated": 0,
   139|   105|    "trades_opened": 0,
   140|   106|    "trades_closed": 0,
   141|   107|    "total_pnl": 0.0,
   142|   108|    "win_count": 0,
   143|   109|    "loss_count": 0,
   144|   110|    "max_drawdown": 0.0,
   145|   111|    "peak_balance": config.initial_balance,
   146|   112|
   147|   113|    # Новое:
   148|   114|    "signals_rejected": 0,       # Общее кол-во отказов
   149|   115|    "signals_per_minute": 0.0,   # Средняя скорость (за 60с)
   150|   116|    "cache_not_warm": 0,         # 1. Кэш не прогрет
   151|   117|    "global_stop_filtered": 0,   # 2. Global protection сработала
   152|   118|    "pairlock_filtered": 0,      # 3. PairLock активен
   153|   119|    "has_position_filtered": 0,  # 4. Уже в позиции
   154|   120|    "rejected_spread": 0,        # 5a. Спред > max
   155|   121|    "rejected_iceberg": 0,       # 5b. Iceberg
   156|   122|    "rejected_confirm_ticks": 0, # 5c. Не хватило тиков
   157|   123|    "rejected_no_signal": 0,     # 5d. analyze() → None (без явной причины)
   158|   124|    "rejected_gatekeeper": 0,    # 6. confirm_trade_entry → False
   159|   125|    "rejected_wallet": 0,        # 7. Не хватило баланса
   160|   126|
   161|   127|    # Время последнего сигнала (для индикатора «жива ли стратегия»)
   162|   128|    "last_signal_at": None,
   163|   129|    "last_signal_type": None,
   164|   130|    "last_rejection_reason": None,
   165|   131|}
   166|   132|```
   167|   133|
   168|   134|#### 1.2 Вставляем счётчики в `_on_snapshot()`
   169|   135|
   170|   136|Для каждого `return` в `_on_snapshot()`:
   171|   137|
   172|   138|```python
   173|   139|# Было:
   174|   140|if not self.cache.is_warm:
   175|   141|    return
   176|   142|
   177|   143|# Стало:
   178|   144|if not self.cache.is_warm:
   179|   145|    self.metrics["cache_not_warm"] += 1
   180|   146|    self._record_signal(None, "cache_not_warm")
   181|   147|    return
   182|   148|
   183|   149|# Аналогично для:
   184|   150|# - protection.global_stop() → metrics["global_stop_filtered"]
   185|   151|# - pairlock.is_locked()    → metrics["pairlock_filtered"]
   186|   152|# - snap.pair in trades     → metrics["has_position_filtered"]
   187|   153|# - snap.spread_pct > cfg   → metrics["rejected_spread"]
   188|   154|# - is_iceberg()            → metrics["rejected_iceberg"]
   189|   155|# - len(window) < ticks     → metrics["rejected_confirm_ticks"]
   190|   156|# - analyze → None          → metrics["rejected_no_signal"]
   191|   157|# - confirm_entry → False   → metrics["rejected_gatekeeper"]
   192|   158|# - stake ≤ 0               → metrics["rejected_wallet"]
   193|   159|```
   194|   160|
   195|   161|Также считаем `signals_per_minute` — скользящее среднее:
   196|   162|
   197|   163|```python
   198|   164|# В _on_snapshot, в самом начале:
   199|   165|now = datetime.now(timezone.utc)
   200|   166|self._signal_timestamps.append(now)
   201|   167|# Чистим старые (>60с)
   202|   168|cutoff = now - timedelta(seconds=60)
   203|   169|while self._signal_timestamps and self._signal_timestamps[0] < cutoff:
   204|   170|    self._signal_timestamps.popleft()
   205|   171|self.metrics["signals_per_minute"] = len(self._signal_timestamps)
   206|   172|```
   207|   173|
   208|   174|#### 1.3 Добавляем `_record_signal()` и `_signal_history`
   209|   175|
   210|   176|```python
   211|   177|# В __init__:
   212|   178|self._signal_history: deque[dict] = deque(maxlen=100)  # 100 записей
   213|   179|self._signal_timestamps: deque[datetime] = deque()      # для signals_per_minute
   214|   180|
   215|   181|# Новый метод:
   216|   182|def _record_signal(self, signal_type: str | None, status: str, detail: str = ""):
   217|   183|    """Записать событие сигнала в историю.
   218|   184|    
   219|   185|    signal_type: "imbalance_buy", "spread_capture", None (нет сигнала)
   220|   186|    status: "accepted" | "rejected" | "filtered"
   221|   187|    detail: причина отказа
   222|   188|    """
   223|   189|    self._signal_history.append({
   224|   190|        "timestamp": datetime.now(timezone.utc).isoformat(),
   225|   191|        "signal_type": signal_type or "none",
   226|   192|        "status": status,
   227|   193|        "detail": detail,
   228|   194|    })
   229|   195|```
   230|   196|
   231|   197|#### 1.4 Добавляем `_record_signal()` во все точки выхода `_on_snapshot()`
   232|   198|
   233|   199|Где нет signal object — передаём `None`:
   234|   200|```python
   235|   201|self._record_signal(None, "filtered", "cache_not_warm")
   236|   202|self._record_signal(None, "filtered", f"spread={snap.spread_pct:.4f} > {c.max_spread_pct}")
   237|   203|self._record_signal(None, "filtered", "iceberg")
   238|   204|self._record_signal(None, "filtered", f"confirm_ticks={len(window)}/{c.confirmation_ticks}")
   239|   205|self._record_signal(None, "filtered", "pairlock")
   240|   206|self._record_signal(None, "filtered", "has_position")
   241|   207|self._record_signal(None, "filtered", "global_stop")
   242|   208|self._record_signal(None, "filtered", "gatekeeper")
   243|   209|self._record_signal(None, "filtered", "wallet")
   244|   210|```
   245|   211|
   246|   212|Где есть signal — передаём его тип:
   247|   213|```python
   248|   214|self._record_signal(signal.entry_tag, "accepted", signal.reason)
   249|   215|```
   250|   216|
   251|   217|#### 1.5 Добавляем `logger.debug()` на каждый отказ
   252|   218|
   253|   219|```python
   254|   220|logger.debug(
   255|   221|    "[OBEngine] REJECT %s | %s | conf=%d snap=%d",
   256|   222|    snap.pair, reason, c.confirmation_ticks, len(window)
   257|   223|)
   258|   224|```
   259|   225|
   260|   226|#### 1.6 Расширяем `status` property
   261|   227|
   262|   228|```python
   263|   229|@property
   264|   230|def status(self) -> dict:
   265|   231|    return {
   266|   232|        # ...было...
   267|   233|        "metrics": {k: round(v, 2) if isinstance(v, float) else v for k, v in self.metrics.items()},
   268|   234|        "active_locks": self.pairlock.active_locks,
   269|   235|        # НОВОЕ:
   270|   236|        "recent_signals": list(self._signal_history)[-20:],  # последние 20
   271|   237|        "signals_per_minute": self.metrics["signals_per_minute"],
   272|   238|    }
   273|   239|```
   274|   240|
   275|   241|### Проверка после этапа
   276|   242|
   277|   243|1. `cd backend && python -c "from app.services.trading.orderbook.engine import OrderBookEngine; print('OK')"` — импорт без ошибок
   278|   244|2. `pytest tests/ -x -k orderbook` — тесты не сломались (если есть)
   279|   245|3. Проверить что `_signal_timestamps` не имеет race condition (использует `async with self._lock`)
   280|   246|
   281|   247|### Зависимость с фронтом
   282|   248|
   283|   249|На этом этапе данные только живут в памяти engine. Фронт их не видит — это нормально. Начинаем наполнять данные.
   284|   250|
   285|   251|

## 🔵 Приоритет 3: Signal метрики в БД — ВЫПОЛНЕН

### Что сделано

**Файлы:**
- `backend/app/models/trading.py`
- `backend/alembic/versions/8425e4763976_add_signal_metrics_to_ob_runs.py`
- `backend/app/services/trading/scheduler.py`
- `backend/app/schemas/trading.py`

**Изменения:**

1. **models/trading.py:**
   - 7 новых полей в `OrderBookRun`: signals_total, signals_rejected, signals_per_minute, last_signal_at, last_signal_type, last_rejection_reason, signal_summary_json

2. **Миграция:**
   - `alembic upgrade head` — ✅ накатилась
   - Добавлено 7 колонок в таблицу `orderbook_runs`

3. **scheduler.py — `_save_ob_live_status()`:**
   - Читает `engine.metrics` каждые 3 сек
   - Сохраняет: signals_total, signals_rejected, signals_per_minute
   - Формирует `signal_summary_json` — только счётчики > 0
   - Сохраняет `last_signal_at`, `last_signal_type`, `last_rejection_reason`

4. **schemas/trading.py:**
   - 7 новых полей в `OrderBookRunResponse`

**Проверка:**
- `OrderBookRunResponse.model_fields` — 23 поля, все 7 новых есть ✅
- `alembic upgrade head` — ✅
- `python3 -c "from app.models.trading import OrderBookRun"` — ✅

---

---
   286|   252|
   287|   253|## 🟡 Приоритет 2: API эндпоинт live-статуса (бэкенд)
   288|   254|
   289|   255|### Где меняем
   290|   256|
   291|   257|**Файлы:**
   292|   258|- `backend/app/api/v1/orderbook.py` — новый эндпоинт
   293|   259|- `backend/app/schemas/trading.py` — новая Pydantic-схема
   294|   260|- `backend/app/services/trading/scheduler.py` — чтобы достать engine по run_id
   295|   261|
   296|   262|### Что делаем
   297|   263|
   298|   264|#### 2.1 Добавляем метод в scheduler для доступа к engine
   299|   265|
   300|   266|```python
   301|   267|# В scheduler.py:
   302|   268|def get_engine_status(self, run_id: int) -> dict | None:
   303|   269|    """Получить live-статус engine по run_id."""
   304|   270|    engine = self._engines.get(run_id)
   305|   271|    if engine is None:
   306|   272|        return None
   307|   273|    return engine.status
   308|   274|```
   309|   275|
   310|   276|Добавить `_engines: dict[int, OrderBookEngine]` в `TradingScheduler.__init__()`:
   311|   277|```python
   312|   278|self._engines: dict[int, OrderBookEngine] = {}
   313|   279|```
   314|   280|
   315|   281|Сохранять engine при старте:
   316|   282|```python
   317|   283|# В start_orderbook_run():
   318|   284|engine = OrderBookEngine(ob_config)
   319|   285|self._engines[run_id] = engine  # ← НОВОЕ
   320|   286|task = asyncio.create_task(...)
   321|   287|```
   322|   288|
   323|   289|Удалять при завершении:
   324|   290|```python
   325|   291|# В _run_orderbook_engine(), в finally:
   326|   292|self._engines.pop(run_id, None)
   327|   293|```
   328|   294|
   329|   295|#### 2.2 Pydantic-схема для статуса
   330|   296|
   331|   297|```python
   332|   298|# В schemas/trading.py:
   333|   299|class OrderBookStatusResponse(BaseModel):
   334|   300|    running: bool
   335|   301|    pair: str
   336|   302|    strategy: str
   337|   303|    balance: float
   338|   304|    signals_per_minute: float
   339|   305|    metrics: dict
   340|   306|    open_trades: dict
   341|   307|    active_locks: list
   342|   308|    recent_signals: list[dict]  # последние 20
   343|   309|```
   344|   310|
   345|   311|#### 2.3 Новый эндпоинт
   346|   312|
   347|   313|```python
   348|   314|@router.get("/runs/{run_id}/status", response_model=OrderBookStatusResponse)
   349|   315|async def get_orderbook_run_status(
   350|   316|    run_id: int,
   351|   317|    current_user: User = Depends(get_current_user),
   352|   318|    session: AsyncSession = Depends(get_session),
   353|   319|) -> OrderBookStatusResponse:
   354|   320|    # Проверить что run принадлежит пользователю
   355|   321|    stmt = select(DBOrderBookRun).where(
   356|   322|        DBOrderBookRun.id == run_id,
   357|   323|        DBOrderBookRun.user_id == current_user.id,
   358|   324|    )
   359|   325|    result = await session.execute(stmt)
   360|   326|    db_run = result.scalar_one_or_none()
   361|   327|    if not db_run:
   362|   328|        raise HTTPException(status_code=404, detail="Run not found")
   363|   329|
   364|   330|    status = scheduler.get_engine_status(run_id)
   365|   331|    if status is None:
   366|   332|        raise HTTPException(status_code=404, detail="Engine not running")
   367|   333|
   368|   334|    return OrderBookStatusResponse(**status)
   369|   335|```
   370|   336|
   371|   337|### Проверка после этапа
   372|   338|
   373|   339|1. Запустить бэкенд: `cd backend && PYTHONPATH=$PWD uvicorn app.main:app`
   374|   340|2. Создать тестовый OB-запуск
   375|   341|3. Вызвать `curl http://localhost:8000/api/v1/orderbook/runs/{id}/status`
   376|   342|4. Проверить что возвращается полный статус с метриками
   377|   343|5. `dart analyze` — импорт схемы не сломал фронт (опционально)
   378|   344|
   379|   345|### Как работает с фронтом
   380|   346|
   381|   347|Фронт будет дёргать `GET /runs/{id}/status` раз в 2-3 секунды для активных запусков. Получает все метрики + recent_signals.
   382|   348|
   383|   349|---
   384|   350|
   385|   351|## 🔵 Приоритет 3: Signal History Buffer + метрики в БД (live-сохранение)
   386|   352|
   387|   353|### Где меняем
   388|   354|
   389|   355|**Файлы:**
   390|   356|- `backend/app/models/trading.py` — новые поля OrderBookRun
   391|   357|- `backend/app/services/trading/scheduler.py` — расширить `_save_ob_live_status()`
   392|   358|- `backend/app/schemas/trading.py` — расширить OrderBookRunResponse
   393|   359|
   394|   360|### Что делаем
   395|   361|
   396|   362|#### 3.1 Новые поля в OrderBookRun
   397|   363|
   398|   364|```python
   399|   365|class OrderBookRun(Base):
   400|   366|    # ...существующие поля...
   401|   367|    
   402|   368|    # НОВОЕ: live-метрики (обновляются каждые 3 сек)
   403|   369|    signals_total = Column(Integer, nullable=True, default=0)
   404|   370|    signals_rejected = Column(Integer, nullable=True, default=0)
   405|   371|    signals_per_minute = Column(Float, nullable=True, default=0.0)
   406|   372|    
   407|   373|    # НОВОЕ: последний сигнал (для визуала)
   408|   374|    last_signal_at = Column(DateTime(timezone=True), nullable=True)
   409|   375|    last_signal_type = Column(String(50), nullable=True)
   410|   376|    last_rejection_reason = Column(String(200), nullable=True)
   411|   377|    
   412|   378|    # НОВОЕ: сигнальное резюме (JSON-строка)
   413|   379|    signal_summary_json = Column(Text, nullable=True)
   414|   380|```
   415|   381|
   416|   382|#### 3.2 Расширяем `_save_ob_live_status()`
   417|   383|
   418|   384|```python
   419|   385|# В scheduler.py _save_ob_live_status():
   420|   386|# Взять метрики из engine
   421|   387|metrics = getattr(engine, "metrics", {})
   422|   388|signals_generated = metrics.get("signals_generated", 0)
   423|   389|
   424|   390|# Сигнальное резюме (топ-5 причин отказов)
   425|   391|rejection_breakdown = {
   426|   392|    k: v for k, v in metrics.items()
   427|   393|    if k.startswith("rejected_") or k.endswith("_filtered")
   428|   394|}
   429|   395|
   430|   396|values = {
   431|   397|    "current_balance": current_balance,
   432|   398|    "open_trade_json": json.dumps(open_trade) if open_trade else None,
   433|   399|    # НОВОЕ:
   434|   400|    "signals_total": signals_generated,
   435|   401|    "signals_rejected": metrics.get("signals_rejected", 0),
   436|   402|    "signals_per_minute": metrics.get("signals_per_minute", 0.0),
   437|   403|    "last_signal_at": metrics.get("last_signal_at"),
   438|   404|    "last_signal_type": metrics.get("last_signal_type"),
   439|   405|    "last_rejection_reason": metrics.get("last_rejection_reason"),
   440|   406|    "signal_summary_json": json.dumps(rejection_breakdown),
   441|   407|}
   442|   408|```
   443|   409|
   444|   410|#### 3.3 Нужна миграция
   445|   411|
   446|   412|```bash
   447|   413|cd backend && PYTHONPATH=$PWD alembic revision --autogenerate -m "add signal metrics to ob runs"
   448|   414|# Проверить сгенерированный файл
   449|   415|cd backend && PYTHONPATH=$PWD alembic upgrade head
   450|   416|```
   451|   417|
   452|   418|### Проверка после этапа
   453|   419|
   454|   420|1. Миграция выполняется без ошибок
   455|   421|2. При live-запуске — поля `signals_total`, `signals_rejected` заполняются
   456|   422|3. `curl .../orderbook/runs/{id}` — возвращает новые поля
   457|   423|
   458|   424|### Как работает с фронтом
   459|   425|
   460|   426|Фронт получает метрики через существующий `GET /runs/{id}` (который дёргается раз в 5 сек). Без нового эндпоинта — данные уже в ответе.
   461|   427|
   462|   428|---
   463|   429|
   464|   430|## 🟢 Приоритет 4: Фронт — блок активности сигналов на RunDetailPage
   465|   431|
   466|   432|### Где меняем
   467|   433|
   468|   434|**Файл:**
   469|   435|- `app/lib/features/trading/presentation/orderbook_run_detail_page.dart`
   470|   436|- `app/lib/features/trading/data/trading_repository.dart` — новый метод
   471|   437|
   472|   438|### Что делаем
   473|   439|
   474|   440|#### 4.1 Новый метод в репозитории
   475|   441|
   476|   442|```dart
   477|   443|Future<Map<String, dynamic>> getOrderBookRunStatus(int runId) async {
   478|   444|  final response = await client.get('/api/v1/orderbook/runs/$runId/status');
   479|   445|  return response.data as Map<String, dynamic>;
   480|   446|}
   481|   447|```
   482|   448|
   483|   449|#### 4.2 Новый блок «Активность сигналов» на RunDetailPage
   484|   450|
   485|   451|Расположить **после баланса, перед настройками** (или наоборот — смотрим).
   486|   452|
   487|   453|```dart
   488|   454|Widget _buildSignalActivity(PfColors pc) {
   489|   455|  // Если запуск не running — не показываем
   490|   456|  if (_run?['status'] != 'running') return const SizedBox();
   491|   457|  
   492|   458|  // Берём из _run (сохраняется в БД) или из _liveStatus (если есть)
   493|   459|  final total = _run?['signals_total'] as int? ?? 0;
   494|   460|  final rejected = _run?['signals_rejected'] as int? ?? 0;
   495|   461|  final spm = (_run?['signals_per_minute'] as num?)?.toDouble() ?? 0;
   496|   462|  
   497|   463|  final accepted = total - rejected;
   498|   464|  final rejectRate = total > 0 ? (rejected / total * 100) : 0.0;
   499|   465|  
   500|   466|  return PfCard(
   501|
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
