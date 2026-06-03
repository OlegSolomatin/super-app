# План улучшения торговых стратегий

> Последнее обновление: 2026-06-01
> Статус: ✅ Все 7 фаз завершены — 19 файлов переработано

## Текущее состояние

- **21 стратегия** в коде
- **✅ Все 17 не-молотных стратегий улучшены** (Фазы 1-7)
- **4 молот-стратегии** (Hammer, Inverse Hammer, All Pairs) — улучшены ранее (ATR, PairLock, динамический TP)

---

## 🔍 Общие проблемы (найдены аудитом)

| # | Проблема | Описание |
|---|----------|----------|
| ❌ | `exit_target = None` | Только hammer/inverse_hammer задают динамический TP. Остальные 15 стратегий полагаются на фиксированный % из конфига |
| ❌ | Trend filter для SELL — баг | Все стратегии проверяют `close > SMA(200)` даже для SELL-сигналов. Логически SELL должен проверять `close < SMA(200)` |
| ❌ | No ATR-based SL в virtual_live | `run_virtual_live()` использует только фиксированный `stop_loss_percent`, без ATR-SL (в `_execute()` ATR-SL есть) |
| ❌ | No volume confirmation | 10 из 17 стратегий не проверяют объём |
| ❌ | No exit-signals | Только RSI Oversold генерирует exit-сигналы. Остальные 16 полагаются только на SL/TP |
| ❌ | Confidence не фильтруется | Engine не проверяет `min_confidence` — сигнал с confidence=0.01 проходит |
| ❌ | `_locked_pairs` не инициализирован | В `__init__` нет `self._locked_pairs = set()` — PairLock может упасть |
| ⚠️ | Мало настраиваемых параметров | Только PSAR, ADX, Supertrend имеют параметры в `__init__`. Остальные — хардкод |

---

## 🟡 Фаза 1: Engine — фундамент (1 файл)

**Файл:** `backend/app/services/trading/engine.py`
**Эффект:** все стратегии сразу получают улучшения

### Задачи

- [x] **ATR-based SL для virtual_live** — скопировать логику ATR-SL из `_execute()` (строки 616-620) в `_execute_virtual_live()` (строка 445)
- [x] **`_locked_pairs` инициализация** — `self._locked_pairs: set[str] = set()` в `__init__`
- [x] **Min confidence filter** — в entry-loop отсеивать сигналы с `confidence < 0.3`
- [x] **ATR-based дефолтный exit_target** — если `sig.exit_target is None`, engine рассчитывает: BUY = entry + ATR×2, SELL = entry − ATR×2

---

## 🟠 Фаза 2: Trend-following (5 стратегий)

### 1️⃣ `ma_crossover.py`
**Сейчас:** SMA20/50 crossover + SMA(200) trend filter

- [x] `exit_target` — BUY: entry + ATR×2, SELL: entry − ATR×2 (через engine)
- [x] Trend filter по направлению: BUY → close > SMA, SELL → close < SMA
- [x] Volume confirmation при crossover
- [x] Параметры: `fast_period=20, slow_period=50, min_gap_pct=0.001`

### 2️⃣ `triple_ma.py`
**Сейчас:** SMA10/30/50 alignment

- [x] `exit_target` — BUY: entry + ATR×2, SELL: entry − ATR×2 (через engine)
- [x] Trend filter по направлению
- [x] Volume confirmation
- [x] Exit-signal: когда alignment ломается (fast < mid)
- [x] Параметры: `fast_period=10, mid_period=30, slow_period=50`

### 3️⃣ `macd_crossover.py`
**Сейчас:** MACD(21,50,10) histogram + close > SMA50

- [x] `exit_target` — BUY: entry + ATR×2, SELL: entry − ATR×2 (через engine)
- [x] Volume confirmation
- [x] Exit-signal: histogram меняет знак
- [x] Параметры: `fast_period=21, slow_period=50, signal_period=10`

### 4️⃣ `adx.py`
**Сейчас:** ADX > 30 + +DI > -DI

- [x] `exit_target` — BUY: entry + ATR×2, SELL: entry − ATR×2 (через engine)
- [x] Volume confirmation
- [x] Exit-signal: ADX падает ниже threshold
- [x] `adx_threshold=30.0` параметр

### 5️⃣ `supertrend.py`
**Сейчас:** ATR(14) bands + multiplier (уже хорошо)

- [x] `exit_target` — BUY: entry + ATR×1.5, SELL: entry − ATR×1.5 (через engine)
- [x] Volume confirmation при флипе тренда

---

## 🟢 Фаза 3: Momentum/Осцилляторы (4 стратегии)

### 6️⃣ `rsi_oversold.py`
**Сейчас:** RSI < 25/>75 + exit при RSI > 60/<40

- [x] `exit_target` — BUY: entry + ATR×2 (через engine)
- [x] Параметры: `oversold=25, overbought=75, exit_buy=60, exit_sell=40`
- [x] Направленный trend filter + volume confirm

### 7️⃣ `stochastic.py`
**Сейчас:** %K < 15/>85 + %K/%D crossover

- [x] `exit_target` — BUY: entry + ATR×2, SELL: entry − ATR×2 (через engine)
- [x] Направленный trend filter
- [x] Volume confirmation
- [x] Параметры: `k_period=14, oversold=15, overbought=85`

### 8️⃣ `rsi_ma_combo.py`
**Сейчас:** RSI < 45 + close > SMA20 / RSI > 55 + close < SMA20

- [x] `exit_target` — BUY: entry + ATR×2, SELL: entry − ATR×2 (через engine)
- [x] Добавлен долгосрочный SMA(200) trend filter (был баг — не использовался)
- [x] Volume confirmation
- [x] Exit при пересечении RSI=50

### 9️⃣ `parabolic_sar.py`
**Сейчас:** SAR flip detection (уже ускорение 0.03, max 0.10)

- [x] `exit_target` — BUY: entry + ATR×1.5, SELL: entry − ATR×1.5 (через engine)
- [x] Направленный trend filter
- [x] Volume confirmation при флипе

---

## 🔵 Фаза 4: Breakout/Volatility (4 стратегии)

### 🔟 `atr_breakout.py`
**Сейчас:** ATR(14)×2 breakout + volume confirm (уже хорошо)

- [x] `exit_target` (через engine)
- [x] 2-candle confirmation (close must also break previous high/low)
- [x] Направленный trend filter
- [x] Параметры: `atr_period=14, multiplier=2.0`

### 1️⃣1️⃣ `bollinger_bands.py`
**Сейчас:** Touch lower/upper band + SMA50

- [x] `exit_target` (через engine)
- [x] Exit-signal: возврат к middle band
- [x] Volume confirmation при пробое
- [x] Параметры: `bb_period=20, bb_std=2.0`
- [x] Направленный trend filter

### 1️⃣2️⃣ `keltner_channels.py`
**Сейчас:** EMA20 + ATR×2.5 bands + RSI filter (уже хорошо)

- [x] `exit_target` (через engine)
- [x] `multiplier` в `__init__`
- [x] Направленный trend filter
- [x] Volume confirmation

### 1️⃣3️⃣ `donchian.py`
**Сейчас:** Breakout 20-period high/low + ATR filter

- [x] `exit_target` (через engine)
- [x] Exit-signal: возврат внутрь канала
- [x] Направленный trend filter
- [x] Volume confirmation
- [x] ATR filter вынесен в отдельный метод

---

## 🟣 Фаза 5: Candlestick patterns (3 стратегии) — по образу молота

### 1️⃣4️⃣ `engulfing.py`
**Сейчас:** Body engulf + volume confirm (SMA200 — баг для SELL)

- [x] `exit_target = candle_range` (как в молоте)
- [x] Trend filter по направлению: BUY → close > SMA, SELL → close < SMA
- [x] `min_engulf_ratio=1.0` параметр

### 1️⃣5️⃣ `doji.py`
**Сейчас:** body < 3% range + 2+ prior candles (SMA200 — баг для SELL)

- [x] `exit_target` — BUY: entry + candle_range (как молот)
- [x] Trend filter по направлению
- [x] Volume: doji на низком объёме (avg за 5 свечей)
- [x] `doji_threshold=0.03, min_prior=2`

### 1️⃣6️⃣ `three_soldiers.py`
**Сейчас:** 3 bullish/bearish candles + body/range ratio (SMA200 — баг для SELL)

- [x] `exit_target` — BUY: entry + avg_candle_range
- [x] Trend filter по направлению
- [x] Volume confirmation: volume must expand on each soldier
- [x] Exit-signal: при закрытии противоположной свечи

---

## 🔴 Фаза 6: Volume-based (1 стратегия)

### 1️⃣7️⃣ `obv.py`
**Сейчас:** OBV divergence over 5 periods (сырая)

- [x] `exit_target` (через engine)
- [x] Направленный trend filter
- [x] `lookback=5` в `__init__`
- [x] Confidence: нормализация OBV/volume (вместо `strength / 100000`)
- [x] 2-candle confirmation (дивергенция на 2+ свечах подряд)

---

## 🎯 Фаза 7: VWAP (1 стратегия, low priority)

### 1️⃣8️⃣ `vwap.py`
**Сейчас:** Price 2% below/above VWAP (нет exit_target, нет volume, SELL без фильтра)

- [x] `exit_target = VWAP` (mean reversion)
- [x] Направленный trend filter (SELL: close < SMA, BUY: close > SMA)
- [x] Volume confirmation
- [x] Exit при возврате к VWAP
- [x] `deviation_pct=0.02, sma50_period=50` параметры

---

## 📊 Сводка по файлам

| Файл | Фаза | Сложность |
|------|------|-----------|
| `engine.py` | 1 | ⭐ |
| `ma_crossover.py` | 2 | ⭐⭐ |
| `triple_ma.py` | 2 | ⭐⭐ |
| `macd_crossover.py` | 2 | ⭐⭐ |
| `adx.py` | 2 | ⭐⭐ |
| `supertrend.py` | 2 | ⭐ |
| `rsi_oversold.py` | 3 | ⭐ |
| `stochastic.py` | 3 | ⭐⭐ |
| `rsi_ma_combo.py` | 3 | ⭐ |
| `parabolic_sar.py` | 3 | ⭐ |
| `atr_breakout.py` | 4 | ⭐ |
| `bollinger_bands.py` | 4 | ⭐⭐ |
| `keltner_channels.py` | 4 | ⭐ |
| `donchian.py` | 4 | ⭐ |
| `engulfing.py` | 5 | ⭐ |
| `doji.py` | 5 | ⭐ |
| `three_soldiers.py` | 5 | ⭐ |
| `obv.py` | 6 | ⭐⭐ |
| `vwap.py` | 7 | ⭐ |

**Итого:** 18 файлов (1 engine + 17 стратегий)
