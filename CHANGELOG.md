# Changelog

| 2026-06-04 | feat | Фаза 0 OB System: модели данных (OrderBookSnapshot, Signal, Trade, ExitType, Cache, Config) + структура папок | Hermes
| 2026-06-04 | fix | Login: очистка токенов при ошибке загрузки профиля + UserProvider.clear() в logout. build v65 | Hermes
| 2026-06-04 | fix | BrainPage: отключена бесконечная анимация force-directed графа, AnimatedSwitcher→условный рендеринг. Чинит: белый экран + неработающую кнопку переключения табов. build v64 | Hermes

## 2026-06-01 — 🎯 Все 7 фаз улучшения торговых стратегий завершены

**Полный аудит и переработка 17 стратегий + engine (19 файлов)**

**Фаза 1 — Engine (engine.py):**
- ATR-based SL в virtual_live режиме (ранее был только фикс.%)
- `_locked_pairs` инициализация (чинит `AttributeError`)
- `min_confidence = 0.3` фильтр при entry
- ATR-based дефолтный exit_target (entry ± ATR×2), если стратегия не задала свой

**Фаза 2 — Trend-following (5 стратегий):**
- ma_crossover, triple_ma, macd_crossover, adx, supertrend
- 🐛 Критический баг: trend filter для SELL требовал `close > SMA` (SELL никогда не срабатывал)
- Добавлены: направленный trend filter, volume confirmation, exit-signals, параметры в __init__

**Фаза 3 — Momentum/Осцилляторы (4 стратегии):**
- rsi_oversold, stochastic, rsi_ma_combo, parabolic_sar
- 🐛 rsi_ma_combo: trend_filter_period (SMA200) был в __init__ но НЕ ИСПОЛЬЗОВАЛСЯ в analyze()
- Добавлены: направленный trend filter, volume confirmation, exit-signals

**Фаза 4 — Breakout/Volatility (4 стратегии):**
- atr_breakout, bollinger_bands, keltner_channels, donchian
- 2-candle confirmation для breakout, exit при возврате в канал/к middle
- ATR filter вынесен в отдельный метод (donchian)

**Фаза 5 — Candlestick Patterns (3 стратегии) — по образу молота:**
- engulfing, doji, three_soldiers
- exit_target = candle_range (как в Hammer)
- Направленный trend filter, volume confirmation

**Фаза 6 — Volume (1 стратегия):**
- obv: 🐛 confidence = `strength / 100000` заменён на нормализацию OBV/volume
- 2-candle confirmation дивергенции

**Фаза 7 — VWAP (1 стратегия):**
- 🐛 SELL не имел никакого trend filter
- exit_target = VWAP (mean reversion), exit при возврате к VWAP

- **Редизайн `TradingPage`** — AdaptiveScaffold с trading skin, pill-табы (Active/History), карточки запусков через PfCard + PfBadge, PnL цветом success/destructive, pair в JetBrains Mono, пустые состояния с иконкой
- **Редизайн `WizardPage`** — AdaptiveScaffold, степпер через Card с hairline, шаги цветом success/primary/muted, кнопки навигации через PfButton (outline/primary), setSection(trading) при входе
- **Редизайн `RunDetailPage`** — AdaptiveScaffold, stat-callout стиль (4 stats в ряд), информация через PfCard, сканер-прогресс с LinearProgressIndicator, торговые сделки с pair/type/PnL цветом success/destructive
- **Анализ:** `dart analyze` — 0 errors по всем трём файлам

## 2026-06-01 — Фаза 2: Редизайн навигации и главной

- **Редизайн `adaptive_scaffold.dart`** — сайдбар в стиле Linear (deep dark `#010102`, active indicator слева, avatar+username в footer), топ-бар 64px с иконкой раздела, сайдбар использует SectionTheme для skin'ов
- **Редизайн `dashboard_tile.dart`** — полный переезд с glassmorphism на flat + hairline: убран BackdropFilter/blur/shadows, плоский фон `--card`, 1px `--border`, иконка в flat-градиентном круге 48px
- **Редизайн `home_page.dart`** — убран background radial gradient, убраны старые AppTheme константы, гостевая страница через PfButton, NavDestination с PhosphorIconData + SectionTheme, setSection при навигации
- **Анализ:** `dart analyze` — 0 issues

## 2026-06-01 — Фаза 1: Базовые UI-компоненты
- **Создан `PfButton`** — универсальная кнопка: 7 variant'ов (primary/secondary/ghost/outline/destructive/link), 7 size'ов (sm/md/lg/pill/icon-sm/icon-md/icon-lg), поддержка иконок слева/справа, loading state, expanded режим
- **Создан `PfBadge`** — badge с variant'ами: default/success/destructive/warning/info
- **Создан `PfDivider` / `PfVerticalDivider`** — системные разделители через `--border` токен
- **Создан `PfSkeleton`** — placeholder загрузки с пульсацией (fade in-out)
- **Создан `PfAvatar`** — аватар с fallback initials
- **Анализ:** `dart analyze` — 0 issues

## 2026-06-01 — Фаза 0: Фундамент дизайн-системы

- **Создан `DESIGN.md`** — полный дизайн-спек проекта по Google-спецификации: цвета, типографика, отступы, скругления, компоненты, Do's and Don'ts
- **Созданы токены** — `lib/shared/tokens/`:
  - `pf_colors.dart` — 40+ цветовых констант (dark, light, section accents, chart)
  - `pf_typography.dart` — 12 токенов типографики (Inter + JetBrains Mono)
  - `pf_spacing.dart` — 4px-base шкала отступов
  - `pf_radius.dart` — скругления от xs до pill
- **Создан `section_theme.dart`** — модель SectionTheme с 8 разделами (home, trading, admin, music, video, posts, settings, login) — каждый со своим accent-цветом и иконкой Phosphor
- **Переписан `theme.dart`** — ThemeData через PfColors + SectionTheme. Полностью переработаны все sub-themes (appBar, card, input, button, text, divider, dialog, snackbar, tabBar)
- **Обновлён `theme_provider.dart`** — добавлен `setSection()`, геттер `theme` возвращает ThemeData с учётом skin'а
- **Анализ:** `dart analyze` — 0 issues

## 2026-06-01 — Утверждён план редизайна (единый скелет + skin'ы)

- **Концепция:** единая база (фон, карточки, типографика, навигация) + тематические акцентные цвета под каждый раздел
- **Референсы:** Binance (трейдинг), Linear (админка), Spotify (музыка), YouTube/Netflix (видео), Stripe (настройки/логин)
- **Создан `REDESIGN_PLAN.md`** — полный пошаговый план редизайна всех 11 страниц
- **План создания `DESIGN.md`** — единый дизайн-спек для проекта (Фаза 0)
- **5 фаз выполнения:** Фундамент → Компоненты → Навигация → Страницы → Build
- **Принципы:** никакого glassmorphism, flat + hairline, семантические токены, SectionTheme

## 2026-06-01 — Dynamic pair scanning + progress bar

- **Dynamic pairs:** `pair_list.py` теперь загружает все USDT-пары с Binance (430+) вместо 50 хардкодных. Кэш 5 мин, fallback на хардкод.
- **Progress bar ETA:** на странице деталей сканера — живой прогресс-бар с кол-вом отсканированных пар, текущей парой, PnL, временем и ETA. Обновление раз в 5 сек.
- **API:** добавлен `/api/v1/trading/scan-progress/{run_id}` для фронта.
- **Dynamic TP:** для hammer/inverse_hammer — TP = entry ± (high − low) свечи-сигнала (вместо 5%). Применён ко всем 4 стратегиям.
- **Pair в сделках:** колонка `pair` добавлена в модель Trade, отображается в run_detail_page.
- **Pair-scanner стратегии:** All Pairs Hammer и All Pairs Inverse Hammer — сканируют все 430+ пар в history mode, TF ≥ 30m.
- **UI:** кнопка `?` вместо `!`, пресеты дат в визарде, авто-скрытие virtual/real для сканера.

| 2026-06-01 22:00 | feat | Фаза 2: Trend-following — 5 стратегий улучшены
  — ma_crossover: направленный trend filter (BUY↑SMA, SELL↓SMA), volume confirm, fast/slow_period
  — triple_ma: направленный trend filter, volume confirm, exit-signal при развале alignment
  — macd_crossover: направленный trend filter, volume confirm, exit-signal при смене знака гистограммы
  — adx: направленный trend filter, volume confirm, exit-signal при падении ADX, adx_threshold
  — supertrend: направленный trend filter (фикс бага SELL), volume confirm при флипе | Hermes
| 2026-06-01 22:30 | feat | Фаза 3: Momentum/Осцилляторы — 4 стратегии улучшены
  — rsi_oversold: направленный trend filter, volume confirm, параметры порогов
  — stochastic: направленный trend filter, volume confirm, параметры k_period/oversold/overbought
  — rsi_ma_combo: направленный trend filter (был баг — SMA200 не использовался), volume confirm, exit при RSI=50
  — parabolic_sar: направленный trend filter, volume confirm при флипе SAR | Hermes
| 2026-06-01 22:45 | feat | Фаза 4: Breakout/Volatility — 4 стратегии улучшены
  — atr_breakout: направленный trend filter, volume confirm, 2-candle confirmation, параметры atr_period/multiplier
  — bollinger_bands: направленный trend filter, volume confirm, exit при возврате к middle, параметры bb_period/bb_std
  — keltner_channels: направленный trend filter (фикс бага SELL), volume confirm, параметры ema/atr/multiplier
  — donchian: направленный trend filter, volume confirm, exit при возврате в канал, atr filter вынесен в метод | Hermes
| 2026-06-01 23:00 | feat | Фаза 5: Candlestick Patterns — 3 стратегии по образу молота
  — engulfing: exit_target=candle_range, направленный trend filter, min_engulf_ratio параметр
  — doji: exit_target=candle_range, направленный trend filter, volume (doji на низком объёме), параметры threshold/min_prior
  — three_soldiers: exit_target=avg_candle_range, направленный trend filter, volume expand confirm | Hermes
| 2026-06-01 23:10 | feat | Фаза 6: Volume — OBV стратегия
  — obv: направленный trend filter, 2-candle confirmation, confidence через normalised OBV/volume, параметр lookback | Hermes
| 2026-06-01 23:20 | feat | Фаза 7: VWAP — финальная стратегия
  — vwap: exit_target=VWAP (mean reversion), направленный trend filter (SELL fix), volume confirm, exit при возврате к VWAP, параметр deviation_pct | Hermes
| 2026-06-01 23:45 | fix | Светлая тема в трейдинге — все страницы
  — trading_page: все PfColors.foreground/mutedForeground/surface → pc.*C (темо-зависимые)
  — wizard_page: _PairTile фон через cardTheme, _coinLetterBox через theme (вместо Colors.white), Divider fix, bottom sheet handle через Theme.of
  — run_detail_page: все цвета через pc.* (theme-aware), все build-методы получили pc
  — rebuild: v61 → Flutter web build (56s) | Hermes

- _locked_pairs инициализация в __init__
- min_confidence фильтр (сигналы < 0.3 отсеиваются при entry)
- ATR-based дефолтный exit_target (entry +- ATR*2) в history и virtual_live
- ATR-based SL в virtual_live (выбирается более строгий между ATR-SL и фикс. %) | Hermes
- `feat` Фаза 2: Trend-following — 5 стратегий улучшены

- ma_crossover: направленный trend filter (BUY/SMA, SELL/SMA), volume confirm, параметры fast/slow_period
- triple_ma: направленный trend filter, volume confirm, exit-signal при развале alignment, параметры period\ов | Hermes
- `infra` Telegram Mini App: добавил роуты в super-app proxy на :8790

Mini App URL в BotFather: https://pfumiko.ru/telegram-mini-app.html
- proxy_server.py: маршруты для Mini App HTML из ~/.hermes/hermes-agent/hermes_cli/web_dist/
- Flutter root (/) и assets не затронуты
- BotFather: setChatMenuButton URL обновлён на /telegram-mini-app.html | Hermes
- `fix` HomePage: не показывать красную ошибку 'Не удалось загрузить профиль' для гостей

- _loadUser(): проверяет наличие access_token ДО вызова API
- Если токена нет → сразу гостевой экран, без запроса к API
- Если API вернул ошибку → silent fail (debugPrint), а не красный SnackBar
- build v62 | Hermes
- `fix` Light theme: исправил хардкодные тёмные цвета в общих виджетах и страницах трейдинга

- PfCard: PfColors.card/border → pc.cardC/pc.borderC
- PfDivider: PfColors.border → pc.borderC
- PfBadge: PfColors.muted/mutedForeground → pc.mutedC/pc.mutedForegroundC
- PfButton: PfColors.surface/foreground/border → pc.surfaceC/pc.foregroundC/pc.borderC
- Trading pill tabs: Color(0xFF181A20) → pc.foregroundC
- Wizard progress bar: Color(0xFF181A20) → theme.colorScheme.onPrimary, PfColors.muted → pc.mutedC
- Wizard mode cards, notifications, toggles: isDark ? white : black → pc.mutedC/pc.borderC
- build v63 | Hermes
