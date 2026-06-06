 || 2026-06-06 | feat | OB Wizard: «?» подсказки во всех 7 шагах + «Стандартные» кнопка с пресетами под каждую стратегию. OB Run Detail: «?» подсказки в настройках. build v85 | Hermes
  — Все шаги визарда: заголовок + «Стандартные» + «?» (кроме сводки — только «?»)
  — Параметры стратегий: «?» с пояснением каждого параметра
  — Риски: «?» для SL, Trailing, Offset, MaxHold
  — Точность: «?» для Confirmation Ticks, Max Spread
  — Защиты: «?» для Cooldown, Auto-stop
  — Три пресета «Стандартные»: Imbalance Scalping, Spread Capture, Order Flow Momentum
  — RunDetail: _showHelp + _helpIcon, «?» для 10 ключей конфига
  — dart analyze: 0 errors (3 pre-existing warnings)
  — build v85
    1|# Changelog
     2|
     3||| 2026-06-05 | feat | OrderBook Run Detail: сохранение конфига стратегии (config_json) в БД, отображение настроек на странице запуска. build v83 | Hermes
     4||| 2026-06-05 | fix | Кнопка назад в хедере: теперь использует GoRouter.canPop() вместо Navigator.canPop(), возвращает на предыдущую страницу, а не на главную. build v84 | Hermes
     5||| 2026-06-05 | fix | app_version.dart синхронизирован с pubspec.yaml (1.0.0+84), старый build показывал v82. build v84 (rebuilt) | Hermes
     6|
     7|| 2026-06-04 | feat | Фаза 7-8 OB System UI: TradingPage (две кнопки сввечи/ордербук) + OrderBook Wizard (7 шагов, theme-aware) | Hermes
     8|| 2026-06-04 | feat | Фаза 5-6 OB System: OrderBookEngine (Exit Pipeline: custom_exit, trailing, hard stop, max hold) + run.py CLI | Hermes
     9|| 2026-06-04 | feat | Фаза 0 OB System: модели данных (OrderBookSnapshot, Signal, Trade, ExitType, Cache, Config) + структура папок | Hermes
    10|| 2026-06-04 | fix | Login: очистка токенов при ошибке загрузки профиля + UserProvider.clear() в logout. build v65 | Hermes
    11|| 2026-06-04 | fix | BrainPage: отключена бесконечная анимация force-directed графа, AnimatedSwitcher→условный рендеринг. Чинит: белый экран + неработающую кнопку переключения табов. build v64 | Hermes
    12|
    13|## 2026-06-01 — 🎯 Все 7 фаз улучшения торговых стратегий завершены
    14|
    15|**Полный аудит и переработка 17 стратегий + engine (19 файлов)**
    16|
    17|**Фаза 1 — Engine (engine.py):**
    18|- ATR-based SL в virtual_live режиме (ранее был только фикс.%)
    19|- `_locked_pairs` инициализация (чинит `AttributeError`)
    20|- `min_confidence = 0.3` фильтр при entry
    21|- ATR-based дефолтный exit_target (entry ± ATR×2), если стратегия не задала свой
    22|
    23|**Фаза 2 — Trend-following (5 стратегий):**
    24|- ma_crossover, triple_ma, macd_crossover, adx, supertrend
    25|- 🐛 Критический баг: trend filter для SELL требовал `close > SMA` (SELL никогда не срабатывал)
    26|- Добавлены: направленный trend filter, volume confirmation, exit-signals, параметры в __init__
    27|
    28|**Фаза 3 — Momentum/Осцилляторы (4 стратегии):**
    29|- rsi_oversold, stochastic, rsi_ma_combo, parabolic_sar
    30|- 🐛 rsi_ma_combo: trend_filter_period (SMA200) был в __init__ но НЕ ИСПОЛЬЗОВАЛСЯ в analyze()
    31|- Добавлены: направленный trend filter, volume confirmation, exit-signals
    32|
    33|**Фаза 4 — Breakout/Volatility (4 стратегии):**
    34|- atr_breakout, bollinger_bands, keltner_channels, donchian
    35|- 2-candle confirmation для breakout, exit при возврате в канал/к middle
    36|- ATR filter вынесен в отдельный метод (donchian)
    37|
    38|**Фаза 5 — Candlestick Patterns (3 стратегии) — по образу молота:**
    39|- engulfing, doji, three_soldiers
    40|- exit_target = candle_range (как в Hammer)
    41|- Направленный trend filter, volume confirmation
    42|
    43|**Фаза 6 — Volume (1 стратегия):**
    44|- obv: 🐛 confidence = `strength / 100000` заменён на нормализацию OBV/volume
    45|- 2-candle confirmation дивергенции
    46|
    47|**Фаза 7 — VWAP (1 стратегия):**
    48|- 🐛 SELL не имел никакого trend filter
    49|- exit_target = VWAP (mean reversion), exit при возврате к VWAP
    50|
    51|- **Редизайн `TradingPage`** — AdaptiveScaffold с trading skin, pill-табы (Active/History), карточки запусков через PfCard + PfBadge, PnL цветом success/destructive, pair в JetBrains Mono, пустые состояния с иконкой
    52|- **Редизайн `WizardPage`** — AdaptiveScaffold, степпер через Card с hairline, шаги цветом success/primary/muted, кнопки навигации через PfButton (outline/primary), setSection(trading) при входе
    53|- **Редизайн `RunDetailPage`** — AdaptiveScaffold, stat-callout стиль (4 stats в ряд), информация через PfCard, сканер-прогресс с LinearProgressIndicator, торговые сделки с pair/type/PnL цветом success/destructive
    54|- **Анализ:** `dart analyze` — 0 errors по всем трём файлам
    55|
    56|## 2026-06-01 — Фаза 2: Редизайн навигации и главной
    57|
    58|- **Редизайн `adaptive_scaffold.dart`** — сайдбар в стиле Linear (deep dark `#010102`, active indicator слева, avatar+username в footer), топ-бар 64px с иконкой раздела, сайдбар использует SectionTheme для skin'ов
    59|- **Редизайн `dashboard_tile.dart`** — полный переезд с glassmorphism на flat + hairline: убран BackdropFilter/blur/shadows, плоский фон `--card`, 1px `--border`, иконка в flat-градиентном круге 48px
    60|- **Редизайн `home_page.dart`** — убран background radial gradient, убраны старые AppTheme константы, гостевая страница через PfButton, NavDestination с PhosphorIconData + SectionTheme, setSection при навигации
    61|- **Анализ:** `dart analyze` — 0 issues
    62|
    63|## 2026-06-01 — Фаза 1: Базовые UI-компоненты
    64|- **Создан `PfButton`** — универсальная кнопка: 7 variant'ов (primary/secondary/ghost/outline/destructive/link), 7 size'ов (sm/md/lg/pill/icon-sm/icon-md/icon-lg), поддержка иконок слева/справа, loading state, expanded режим
    65|- **Создан `PfBadge`** — badge с variant'ами: default/success/destructive/warning/info
    66|- **Создан `PfDivider` / `PfVerticalDivider`** — системные разделители через `--border` токен
    67|- **Создан `PfSkeleton`** — placeholder загрузки с пульсацией (fade in-out)
    68|- **Создан `PfAvatar`** — аватар с fallback initials
    69|- **Анализ:** `dart analyze` — 0 issues
    70|
    71|## 2026-06-01 — Фаза 0: Фундамент дизайн-системы
    72|
    73|- **Создан `DESIGN.md`** — полный дизайн-спек проекта по Google-спецификации: цвета, типографика, отступы, скругления, компоненты, Do's and Don'ts
    74|- **Созданы токены** — `lib/shared/tokens/`:
    75|  - `pf_colors.dart` — 40+ цветовых констант (dark, light, section accents, chart)
    76|  - `pf_typography.dart` — 12 токенов типографики (Inter + JetBrains Mono)
    77|  - `pf_spacing.dart` — 4px-base шкала отступов
    78|  - `pf_radius.dart` — скругления от xs до pill
    79|- **Создан `section_theme.dart`** — модель SectionTheme с 8 разделами (home, trading, admin, music, video, posts, settings, login) — каждый со своим accent-цветом и иконкой Phosphor
    80|- **Переписан `theme.dart`** — ThemeData через PfColors + SectionTheme. Полностью переработаны все sub-themes (appBar, card, input, button, text, divider, dialog, snackbar, tabBar)
    81|- **Обновлён `theme_provider.dart`** — добавлен `setSection()`, геттер `theme` возвращает ThemeData с учётом skin'а
    82|- **Анализ:** `dart analyze` — 0 issues
    83|
    84|## 2026-06-01 — Утверждён план редизайна (единый скелет + skin'ы)
    85|
    86|- **Концепция:** единая база (фон, карточки, типографика, навигация) + тематические акцентные цвета под каждый раздел
    87|- **Референсы:** Binance (трейдинг), Linear (админка), Spotify (музыка), YouTube/Netflix (видео), Stripe (настройки/логин)
    88|- **Создан `REDESIGN_PLAN.md`** — полный пошаговый план редизайна всех 11 страниц
    89|- **План создания `DESIGN.md`** — единый дизайн-спек для проекта (Фаза 0)
    90|- **5 фаз выполнения:** Фундамент → Компоненты → Навигация → Страницы → Build
    91|- **Принципы:** никакого glassmorphism, flat + hairline, семантические токены, SectionTheme
    92|
    93|## 2026-06-01 — Dynamic pair scanning + progress bar
    94|
    95|- **Dynamic pairs:** `pair_list.py` теперь загружает все USDT-пары с Binance (430+) вместо 50 хардкодных. Кэш 5 мин, fallback на хардкод.
    96|- **Progress bar ETA:** на странице деталей сканера — живой прогресс-бар с кол-вом отсканированных пар, текущей парой, PnL, временем и ETA. Обновление раз в 5 сек.
    97|- **API:** добавлен `/api/v1/trading/scan-progress/{run_id}` для фронта.
    98|- **Dynamic TP:** для hammer/inverse_hammer — TP = entry ± (high − low) свечи-сигнала (вместо 5%). Применён ко всем 4 стратегиям.
    99|- **Pair в сделках:** колонка `pair` добавлена в модель Trade, отображается в run_detail_page.
   100|- **Pair-scanner стратегии:** All Pairs Hammer и All Pairs Inverse Hammer — сканируют все 430+ пар в history mode, TF ≥ 30m.
   101|- **UI:** кнопка `?` вместо `!`, пресеты дат в визарде, авто-скрытие virtual/real для сканера.
   102|
   103|| 2026-06-01 22:00 | feat | Фаза 2: Trend-following — 5 стратегий улучшены
   104|  — ma_crossover: направленный trend filter (BUY↑SMA, SELL↓SMA), volume confirm, fast/slow_period
   105|  — triple_ma: направленный trend filter, volume confirm, exit-signal при развале alignment
   106|  — macd_crossover: направленный trend filter, volume confirm, exit-signal при смене знака гистограммы
   107|  — adx: направленный trend filter, volume confirm, exit-signal при падении ADX, adx_threshold
   108|  — supertrend: направленный trend filter (фикс бага SELL), volume confirm при флипе | Hermes
   109|| 2026-06-01 22:30 | feat | Фаза 3: Momentum/Осцилляторы — 4 стратегии улучшены
   110|  — rsi_oversold: направленный trend filter, volume confirm, параметры порогов
   111|  — stochastic: направленный trend filter, volume confirm, параметры k_period/oversold/overbought
   112|  — rsi_ma_combo: направленный trend filter (был баг — SMA200 не использовался), volume confirm, exit при RSI=50
   113|  — parabolic_sar: направленный trend filter, volume confirm при флипе SAR | Hermes
   114|| 2026-06-01 22:45 | feat | Фаза 4: Breakout/Volatility — 4 стратегии улучшены
   115|  — atr_breakout: направленный trend filter, volume confirm, 2-candle confirmation, параметры atr_period/multiplier
   116|  — bollinger_bands: направленный trend filter, volume confirm, exit при возврате к middle, параметры bb_period/bb_std
   117|  — keltner_channels: направленный trend filter (фикс бага SELL), volume confirm, параметры ema/atr/multiplier
   118|  — donchian: направленный trend filter, volume confirm, exit при возврате в канал, atr filter вынесен в метод | Hermes
   119|| 2026-06-01 23:00 | feat | Фаза 5: Candlestick Patterns — 3 стратегии по образу молота
   120|  — engulfing: exit_target=candle_range, направленный trend filter, min_engulf_ratio параметр
   121|  — doji: exit_target=candle_range, направленный trend filter, volume (doji на низком объёме), параметры threshold/min_prior
   122|  — three_soldiers: exit_target=avg_candle_range, направленный trend filter, volume expand confirm | Hermes
   123|| 2026-06-01 23:10 | feat | Фаза 6: Volume — OBV стратегия
   124|  — obv: направленный trend filter, 2-candle confirmation, confidence через normalised OBV/volume, параметр lookback | Hermes
   125|| 2026-06-01 23:20 | feat | Фаза 7: VWAP — финальная стратегия
   126|  — vwap: exit_target=VWAP (mean reversion), направленный trend filter (SELL fix), volume confirm, exit при возврате к VWAP, параметр deviation_pct | Hermes
   127|| 2026-06-01 23:45 | fix | Светлая тема в трейдинге — все страницы
   128|  — trading_page: все PfColors.foreground/mutedForeground/surface → pc.*C (темо-зависимые)
   129|  — wizard_page: _PairTile фон через cardTheme, _coinLetterBox через theme (вместо Colors.white), Divider fix, bottom sheet handle через Theme.of
   130|  — run_detail_page: все цвета через pc.* (theme-aware), все build-методы получили pc
   131|  — rebuild: v61 → Flutter web build (56s) | Hermes
   132|
   133|- _locked_pairs инициализация в __init__
   134|- min_confidence фильтр (сигналы < 0.3 отсеиваются при entry)
   135|- ATR-based дефолтный exit_target (entry +- ATR*2) в history и virtual_live
   136|- ATR-based SL в virtual_live (выбирается более строгий между ATR-SL и фикс. %) | Hermes
   137|- `feat` Фаза 2: Trend-following — 5 стратегий улучшены
   138|
   139|- ma_crossover: направленный trend filter (BUY/SMA, SELL/SMA), volume confirm, параметры fast/slow_period
   140|- triple_ma: направленный trend filter, volume confirm, exit-signal при развале alignment, параметры period\ов | Hermes
   141|- `infra` Telegram Mini App: добавил роуты в super-app proxy на :8790
   142|
   143|Mini App URL в BotFather: https://pfumiko.ru/telegram-mini-app.html
   144|- proxy_server.py: маршруты для Mini App HTML из ~/.hermes/hermes-agent/hermes_cli/web_dist/
   145|- Flutter root (/) и assets не затронуты
   146|- BotFather: setChatMenuButton URL обновлён на /telegram-mini-app.html | Hermes
   147|- `fix` HomePage: не показывать красную ошибку 'Не удалось загрузить профиль' для гостей
   148|
   149|- _loadUser(): проверяет наличие access_token ДО вызова API
   150|- Если токена нет → сразу гостевой экран, без запроса к API
   151|- Если API вернул ошибку → silent fail (debugPrint), а не красный SnackBar
   152|- build v62 | Hermes
   153|- `fix` Light theme: исправил хардкодные тёмные цвета в общих виджетах и страницах трейдинга
   154|
   155|- PfCard: PfColors.card/border → pc.cardC/pc.borderC
   156|- PfDivider: PfColors.border → pc.borderC
   157|- PfBadge: PfColors.muted/mutedForeground → pc.mutedC/pc.mutedForegroundC
   158|- PfButton: PfColors.surface/foreground/border → pc.surfaceC/pc.foregroundC/pc.borderC
   159|- Trading pill tabs: Color(0xFF181A20) → pc.foregroundC
   160|- Wizard progress bar: Color(0xFF181A20) → theme.colorScheme.onPrimary, PfColors.muted → pc.mutedC
   161|- Wizard mode cards, notifications, toggles: isDark ? white : black → pc.mutedC/pc.borderC
   162|- build v63 | Hermes
   163|