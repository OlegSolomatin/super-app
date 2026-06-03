# План улучшения торговых стратегий

> Последнее обновление: 2026-06-01
> Статус: ✅ — сделано, 🔄 — в работе, ⬜ — не начато

## Текущее состояние

- **21 стратегия** в коде
- **4 улучшены** (Hammer, Inverse Hammer, All Pairs Hammer, All Pairs Inverse Hammer — ATR, PairLock, динамический TP, смягчение критериев)
- **17 требуют доработки**

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

- [ ] ⬜ `exit_target` — BUY: entry + ATR×2
- [ ] ⬜ Параметры: `rsi_oversold=25, rsi_overbought=75, rsi_exit_buy=60, rsi_exit_sell=40`

### 7️⃣ `stochastic.py`
**Сейчас:** %K < 15/>85 + %K/%D crossover

- [ ] ⬜ `exit_target` — BUY: entry + ATR×2, SELL: entry − ATR×2
- [ ] ⬜ Trend filter по направлению
- [ ] ⬜ Volume confirmation
- [ ] ⬜ Параметры: `k_period=14, oversold=15, overbought=85`

### 8️⃣ `rsi_ma_combo.py`
**Сейчас:** RSI < 45 + close > SMA20 / RSI > 55 + close < SMA20

- [ ] ⬜ `exit_target` — BUY: entry + ATR×2, SELL: entry − ATR×2
- [ ] ⬜ Добавить долгосрочный SMA(200) trend filter поверх
- [ ] ⬜ Volume confirmation

### 9️⃣ `parabolic_sar.py`
**Сейчас:** SAR flip detection (уже ускорение 0.03, max 0.10)

- [ ] ⬜ `exit_target` — BUY: entry + ATR×1.5, SELL: entry − ATR×1.5
- [ ] ⬜ ATR-based адаптивный acceleration factor
- [ ] ⬜ Параметры уже есть

---

## 🔵 Фаза 4: Breakout/Volatility (4 стратегии)

### 🔟 `atr_breakout.py`
**Сейчас:** ATR(14)×2 breakout + volume confirm (уже хорошо)

- [ ] ⬜ `exit_target` — BUY: entry − ATR×0.5 + ATR×2, SELL: entry + ATR×0.5 − ATR×2
- [ ] ⬜ 2-candle confirmation (пробой подтверждён закрытием следующей свечи)

### 1️⃣1️⃣ `bollinger_bands.py`
**Сейчас:** Touch lower/upper band + SMA50

- [ ] ⬜ `exit_target` — BUY/SELL: to middle band (mean reversion)
- [ ] ⬜ Exit-signal: возврат к middle band
- [ ] ⬜ Volume confirmation при пробое
- [ ] ⬜ Параметры: `bb_period=20, bb_std=2.0`

### 1️⃣2️⃣ `keltner_channels.py`
**Сейчас:** EMA20 + ATR×2.5 bands + RSI filter (уже хорошо)

- [ ] ⬜ `exit_target` — BUY: entry − ATR×0.5 + ATR×1.5 (частичный)
- [ ] ⬜ `multiplier` в `__init__`

### 1️⃣3️⃣ `donchian.py`
**Сейчас:** Breakout 20-period high/low + ATR filter

- [ ] ⬜ `exit_target` — BUY: entry + ATR×2, SELL: entry − ATR×2
- [ ] ⬜ Exit-signal: возврат внутрь канала

---

## 🟣 Фаза 5: Candlestick patterns (3 стратегии) — по образу молота

### 1️⃣4️⃣ `engulfing.py`
**Сейчас:** Body engulf + volume confirm (SMA200 — баг для SELL)

- [ ] ⬜ `exit_target = candle_range` (как в молоте)
- [ ] ⬜ Trend filter по направлению: BUY → close > SMA, SELL → close < SMA
- [ ] ⬜ Порог: ratio engulfing >= 1.0

### 1️⃣5️⃣ `doji.py`
**Сейчас:** body < 3% range + 2+ prior candles (SMA200 — баг для SELL)

- [ ] ⬜ `exit_target` — BUY: entry + candle_range (как молот)
- [ ] ⬜ Trend filter по направлению
- [ ] ⬜ Volume: must be lower than prior (doji на низком объёме = сильнее)
- [ ] ⬜ `doji_threshold=0.03, min_prior=2`

### 1️⃣6️⃣ `three_soldiers.py`
**Сейчас:** 3 bullish/bearish candles + body/range ratio (SMA200 — баг для SELL)

- [ ] ⬜ `exit_target` — BUY: entry + avg_candle_range×2
- [ ] ⬜ Trend filter по направлению
- [ ] ⬜ Volume confirmation: volume must expand on each soldier
- [ ] ⬜ Exit-signal: при закрытии противоположной свечи

---

## 🔴 Фаза 6: Volume-based (1 стратегия)

### 1️⃣7️⃣ `obv.py`
**Сейчас:** OBV divergence over 5 periods (сырая)

- [ ] ⬜ `exit_target` — BUY: entry + ATR×2, SELL: entry − ATR×2
- [ ] ⬜ Trend filter: BUY только если SMA(200) восходящий
- [ ] ⬜ `lookback=5` в `__init__`
- [ ] ⬜ Confidence: переписать normalised deviation (вместо `strength / 100000`)

---

## 🎯 Фаза 7: VWAP (1 стратегия, low priority)

### 1️⃣8️⃣ `vwap.py`
**Сейчас:** Price 2% below/above VWAP (нет exit_target, нет volume)

- [ ] ⬜ `exit_target` — BUY/SELL: to VWAP (mean reversion)
- [ ] ⬜ Только если VWAP восходящий для BUY
- [ ] ⬜ `deviation_pct=0.02, lookback=50`

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
