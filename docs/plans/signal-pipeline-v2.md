# 📋 План: Пайплайн сигналов v2 — быстрый, LLM, без дубликатов

> **Цель:** Переписать пайплайн сигналов — rule-based классификация → LLM, ускорение парсера (5s poll), гарантия без дубликатов, мониторинг задержек.

---

## Архитектура

```
[Telegram Канал] ──► [Парсер] ──► Redis PUBLISH ──► [Мэппер (LLM)] ──► Redis PUBLISH ──► [Нотифаер]
                       ↓              channel:signal:new      ↑        channel:signal:mapped   ↓
                   PostgreSQL     ┌──────────┐         available_exchanges           Telegram Bot
                TradingSignal     │ Проверка │           проверены                     ↓
                                  │  бирж    │                                    Сигнал + ✅/❌
                                  └──────────┘
                                       ↓
                                Redis сигналы:latest
                                       ↓
                               SSE поток / API / Сайт
```

---

## ⚙️ Фаза 1 — Конфиг: канал → 2 стратегии + params визарда

**Файл:** `backend/app/services/signals/strategy_config.py` (новый)

Единый источник правды — какие стратегии к какому каналу, и какие у них настройки в визарде.

Структура:
- `CHANNEL_STRATEGIES` — словарь {канал: {strategies: [{id, engine, label, description, wizard_params}]}}
- `get_strategies_for_channel(channel)` — получить 2 варианта для канала
- `build_llm_prompt(channel, pair, data, strategies)` — собрать промпт из сигнала + 2 вариантов

---

## ⚙️ Фаза 2 — LLM классификатор

**Файл:** `backend/app/services/signals/signal_mapper.py` (изменить)

Заменить `classify_signal()` rule-based на LLM-запрос к DeepSeek Flash.

**Новая логика:**
1. Получить сигнал (7 полей)
2. Определить канал → взять 2 варианта из `CHANNEL_STRATEGIES`
3. Для каждого варианта — собрать wizard_params (диапазоны)
4. Отправить LLM-запрос (промпт ~350 токенов)
5. Распарсить JSON-ответ
6. Вернуть `SignalClassification`

**Промпт:**
```
Сигнал: {channel}, {pair}
range: {price_range}%  vol60m: ${vol_60m}  vol10m: ${vol_10m}
slope: {slope}  top_ratio: {top_ratio}  bot_ratio: {bot_ratio}

2 варианта:

A — {strategy_A_id} ({engine_A})
  {params_A}

B — {strategy_B_id} ({engine_B})
  {params_B}

Ответь JSON:
{"variant":"A","strategy":"название","confidence":0.0-1.0,"params":{},"reasoning":"..."}
```

**Добавить в `SignalClassification`:** поле `reasoning: str = ""`

---

## ⚙️ Фаза 3 — Ускорение парсера

**Файл:** `backend/scripts/parse_telegram_signals.py`

Изменить `SLEEP_SECONDS = 5` (было 15).

Ожидаемая задержка обнаружения: 0-5s (вместо 0-15s).

---

## ⚙️ Фаза 4 — Дедупликация (гарантия без дубликатов)

**Файл:** `signal_mapper.py`

Добавить в `map_and_save_signal()`:
```python
if signal.mapped_strategy is not None:
    logger.info("Signal #%d already classified as %s, skipping", signal_id, signal.mapped_strategy)
    return None
```

---

## ⚙️ Фаза 5 — Поле reasoning в модель + схему

**Файлы:**
- `backend/app/models/trading_signal.py` — добавить `reasoning = Column(Text, nullable=True)`
- `backend/app/schemas/trading_signal.py` — добавить `reasoning: Optional[str] = None`
- Создать миграцию Alembic

---

## ⚙️ Фаза 6 — Мониторинг и логирование

Добавить метрики задержки на каждом этапе:
- Парсер: `parse→publish in Xms`
- Мэппер: `LLM classification in Xms`
- Нотифаер: `notifier→telegram in Xms`

---

## ⏱ Ожидаемая задержка

| Этап | Минимум | Максимум |
|------|---------|----------|
| Сигнал появился → обнаружен | ~0s | ~5s |
| Обнаружен → классифицирован | ~1s | ~3.5s |
| Классифицирован → в Telegram | ~0.5s | ~1s |
| Классифицирован → на сайте | ~0.05s | ~0.1s |
| **→ Полный цикл** | **~1.5s** | **~9.5s** |
