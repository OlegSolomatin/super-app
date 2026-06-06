 || 2026-06-06 | feat | OB Engine: счётчики отказов сигналов (20 метрик) + Signal History Buffer (100 записей) + _reject() во всех 3 стратегиях. build v86 (backend only) | Hermes
  — 12 новых счётчиков: signals_rejected, signals_per_minute, cache_not_warm, global_stop_filtered, pairlock_filtered, has_position_filtered, rejected_spread/iceberg/confirm_ticks/no_signal/gatekeeper/wallet
  — _record_signal(): каждый return в _on_snapshot() теперь логируется в history
  — _signal_timestamps: скользящее окно для signals_per_minute
  — Strategy base: _last_rejection + _reject() для детализации причин отказа
  — Все 3 стратегии (imbalance, spread, order_flow): каждый return None вызывает _reject()
  — status property: расширен recent_signals (последние 20 записей)
  — Python import check: ✅ все 5 файлов
    1| || 2026-06-06 | feat | OB Wizard: «?» подсказки во всех 7 шагах + «Стандартные» кнопка с пресетами под каждую стратегию. OB Run Detail: «?» подсказки в настройках. build v85 | Hermes
     2|  — Все шаги визарда: заголовок + «Стандартные» + «?» (кроме сводки — только «?»)
     3|  — Параметры стратегий: «?» с пояснением каждого параметра
     4|  — Риски: «?» для SL, Trailing, Offset, MaxHold
     5|  — Точность: «?» для Confirmation Ticks, Max Spread
     6|  — Защиты: «?» для Cooldown, Auto-stop
     7|  — Три пресета «Стандартные»: Imbalance Scalping, Spread Capture, Order Flow Momentum
     8|  — RunDetail: _showHelp + _helpIcon, «?» для 10 ключей конфига
     9|  — dart analyze: 0 errors (3 pre-existing warnings)
    10|  — build v85
    11|    1|# Changelog
    12|     2|
    13|     3||| 2026-06-05 | feat | OrderBook Run Detail: сохранение конфига стратегии (config_json) в БД, отображение настроек на странице запуска. build v83 | Hermes
    14|     4||| 2026-06-05 | fix | Кнопка назад в хедере: теперь использует GoRouter.canPop() вместо Navigator.canPop(), возвращает на предыдущую страницу, а не на главную. build v84 | Hermes
    15|     5||| 2026-06-05 | fix | app_version.dart синхронизирован с pubspec.yaml (1.0.0+84), старый build показывал v82. build v84 (rebuilt) | Hermes
    16|     6|
    17|     7|| 2026-06-04 | feat | Фаза 7-8 OB System UI: TradingPage (две кнопки сввечи/ордербук) + OrderBook Wizard (7 шагов, theme-aware) | Hermes
    18|     8|| 2026-06-04 | feat | Фаза 5-6 OB System: OrderBookEngine (Exit Pipeline: custom_exit, trailing, hard stop, max hold) + run.py CLI | Hermes
    19|     9|| 2026-06-04 | feat | Фаза 0 OB System: модели данных (OrderBookSnapshot, Signal, Trade, ExitType, Cache, Config) + структура папок | Hermes
    20|    10|| 2026-06-04 | fix | Login: очистка токенов при ошибке загрузки профиля + UserProvider.clear() в logout. build v65 | Hermes
    21|    11|| 2026-06-04 | fix | BrainPage: отключена бесконечная анимация force-directed графа, AnimatedSwitcher→условный рендеринг. Чинит: белый экран + неработающую кнопку переключения табов. build v64 | Hermes
    22|    12|
    23|    13|## 2026-06-01 — 🎯 Все 7 фаз улучшения торговых стратегий завершены
    24|    14|
    25|    15|**Полный аудит и переработка 17 стратегий + engine (19 файлов)**
    26|    16|
    27|    17|**Фаза 1 — Engine (engine.py):**
    28|    18|- ATR-based SL в virtual_live режиме (ранее был только фикс.%)
    29|    19|- `_locked_pairs` инициализация (чинит `AttributeError`)
    30|    20|- `min_confidence = 0.3` фильтр при entry
    31|    21|- ATR-based дефолтный exit_target (entry ± ATR×2), если стратегия не задала свой
    32|    22|
    33|    23|**Фаза 2 — Trend-following (5 стратегий):**
    34|    24|- ma_crossover, triple_ma, macd_crossover, adx, supertrend
    35|    25|- 🐛 Критический баг: trend filter для SELL требовал `close > SMA` (SELL никогда не срабатывал)
    36|    26|- Добавлены: направленный trend filter, volume confirmation, exit-signals, параметры в __init__
    37|    27|
    38|    28|**Фаза 3 — Momentum/Осцилляторы (4 стратегии):**
    39|    29|- rsi_oversold, stochastic, rsi_ma_combo, parabolic_sar
    40|    30|- 🐛 rsi_ma_combo: trend_filter_period (SMA200) был в __init__ но НЕ ИСПОЛЬЗОВАЛСЯ в analyze()
    41|    31|- Добавлены: направленный trend filter, volume confirmation, exit-signals
    42|    32|
    43|    33|**Фаза 4 — Breakout/Volatility (4 стратегии):**
    44|    34|- atr_breakout, bollinger_bands, keltner_channels, donchian
    45|    35|- 2-candle confirmation для breakout, exit при возврате в канал/к middle
    46|    36|- ATR filter вынесен в отдельный метод (donchian)
    47|    37|
    48|    38|**Фаза 5 — Candlestick Patterns (3 стратегии) — по образу молота:**
    49|    39|- engulfing, doji, three_soldiers
    50|    40|- exit_target = candle_range (как в Hammer)
    51|    41|- Направленный trend filter, volume confirmation
    52|    42|
    53|    43|**Фаза 6 — Volume (1 стратегия):**
    54|    44|- obv: 🐛 confidence = `strength / 100000` заменён на нормализацию OBV/volume
    55|    45|- 2-candle confirmation дивергенции
    56|    46|
    57|    47|**Фаза 7 — VWAP (1 стратегия):**
    58|    48|- 🐛 SELL не имел никакого trend filter
    59|    49|- exit_target = VWAP (mean reversion), exit при возврате к VWAP
    60|    50|
    61|    51|- **Редизайн `TradingPage`** — AdaptiveScaffold с trading skin, pill-табы (Active/History), карточки запусков через PfCard + PfBadge, PnL цветом success/destructive, pair в JetBrains Mono, пустые состояния с иконкой
    62|    52|- **Редизайн `WizardPage`** — AdaptiveScaffold, степпер через Card с hairline, шаги цветом success/primary/muted, кнопки навигации через PfButton (outline/primary), setSection(trading) при входе
    63|    53|- **Редизайн `RunDetailPage`** — AdaptiveScaffold, stat-callout стиль (4 stats в ряд), информация через PfCard, сканер-прогресс с LinearProgressIndicator, торговые сделки с pair/type/PnL цветом success/destructive
    64|    54|- **Анализ:** `dart analyze` — 0 errors по всем трём файлам
    65|    55|
    66|    56|## 2026-06-01 — Фаза 2: Редизайн навигации и главной
    67|    57|
    68|    58|- **Редизайн `adaptive_scaffold.dart`** — сайдбар в стиле Linear (deep dark `#010102`, active indicator слева, avatar+username в footer), топ-бар 64px с иконкой раздела, сайдбар использует SectionTheme для skin'ов
    69|    59|- **Редизайн `dashboard_tile.dart`** — полный переезд с glassmorphism на flat + hairline: убран BackdropFilter/blur/shadows, плоский фон `--card`, 1px `--border`, иконка в flat-градиентном круге 48px
    70|    60|- **Редизайн `home_page.dart`** — убран background radial gradient, убраны старые AppTheme константы, гостевая страница через PfButton, NavDestination с PhosphorIconData + SectionTheme, setSection при навигации
    71|    61|- **Анализ:** `dart analyze` — 0 issues
    72|    62|
    73|    63|## 2026-06-01 — Фаза 1: Базовые UI-компоненты
    74|    64|- **Создан `PfButton`** — универсальная кнопка: 7 variant'ов (primary/secondary/ghost/outline/destructive/link), 7 size'ов (sm/md/lg/pill/icon-sm/icon-md/icon-lg), поддержка иконок слева/справа, loading state, expanded режим
    75|    65|- **Создан `PfBadge`** — badge с variant'ами: default/success/destructive/warning/info
    76|    66|- **Создан `PfDivider` / `PfVerticalDivider`** — системные разделители через `--border` токен
    77|    67|- **Создан `PfSkeleton`** — placeholder загрузки с пульсацией (fade in-out)
    78|    68|- **Создан `PfAvatar`** — аватар с fallback initials
    79|    69|- **Анализ:** `dart analyze` — 0 issues
    80|    70|
    81|    71|## 2026-06-01 — Фаза 0: Фундамент дизайн-системы
    82|    72|
    83|    73|- **Создан `DESIGN.md`** — полный дизайн-спек проекта по Google-спецификации: цвета, типографика, отступы, скругления, компоненты, Do's and Don'ts
    84|    74|- **Созданы токены** — `lib/shared/tokens/`:
    85|    75|  - `pf_colors.dart` — 40+ цветовых констант (dark, light, section accents, chart)
    86|    76|  - `pf_typography.dart` — 12 токенов типографики (Inter + JetBrains Mono)
    87|    77|  - `pf_spacing.dart` — 4px-base шкала отступов
    88|    78|  - `pf_radius.dart` — скругления от xs до pill
    89|    79|- **Создан `section_theme.dart`** — модель SectionTheme с 8 разделами (home, trading, admin, music, video, posts, settings, login) — каждый со своим accent-цветом и иконкой Phosphor
    90|    80|- **Переписан `theme.dart`** — ThemeData через PfColors + SectionTheme. Полностью переработаны все sub-themes (appBar, card, input, button, text, divider, dialog, snackbar, tabBar)
    91|    81|- **Обновлён `theme_provider.dart`** — добавлен `setSection()`, геттер `theme` возвращает ThemeData с учётом skin'а
    92|    82|- **Анализ:** `dart analyze` — 0 issues
    93|    83|
    94|    84|## 2026-06-01 — Утверждён план редизайна (единый скелет + skin'ы)
    95|    85|
    96|    86|- **Концепция:** единая база (фон, карточки, типографика, навигация) + тематические акцентные цвета под каждый раздел
    97|    87|- **Референсы:** Binance (трейдинг), Linear (админка), Spotify (музыка), YouTube/Netflix (видео), Stripe (настройки/логин)
    98|    88|- **Создан `REDESIGN_PLAN.md`** — полный пошаговый план редизайна всех 11 страниц
    99|    89|- **План создания `DESIGN.md`** — единый дизайн-спек для проекта (Фаза 0)
   100|    90|- **5 фаз выполнения:** Фундамент → Компоненты → Навигация → Страницы → Build
   101|    91|- **Принципы:** никакого glassmorphism, flat + hairline, семантические токены, SectionTheme
   102|    92|
   103|    93|## 2026-06-01 — Dynamic pair scanning + progress bar
   104|    94|
   105|    95|- **Dynamic pairs:** `pair_list.py` теперь загружает все USDT-пары с Binance (430+) вместо 50 хардкодных. Кэш 5 мин, fallback на хардкод.
   106|    96|- **Progress bar ETA:** на странице деталей сканера — живой прогресс-бар с кол-вом отсканированных пар, текущей парой, PnL, временем и ETA. Обновление раз в 5 сек.
   107|    97|- **API:** добавлен `/api/v1/trading/scan-progress/{run_id}` для фронта.
   108|    98|- **Dynamic TP:** для hammer/inverse_hammer — TP = entry ± (high − low) свечи-сигнала (вместо 5%). Применён ко всем 4 стратегиям.
   109|    99|- **Pair в сделках:** колонка `pair` добавлена в модель Trade, отображается в run_detail_page.
   110|   100|- **Pair-scanner стратегии:** All Pairs Hammer и All Pairs Inverse Hammer — сканируют все 430+ пар в history mode, TF ≥ 30m.
   111|   101|- **UI:** кнопка `?` вместо `!`, пресеты дат в визарде, авто-скрытие virtual/real для сканера.
   112|   102|
   113|   103|| 2026-06-01 22:00 | feat | Фаза 2: Trend-following — 5 стратегий улучшены
   114|   104|  — ma_crossover: направленный trend filter (BUY↑SMA, SELL↓SMA), volume confirm, fast/slow_period
   115|   105|  — triple_ma: направленный trend filter, volume confirm, exit-signal при развале alignment
   116|   106|  — macd_crossover: направленный trend filter, volume confirm, exit-signal при смене знака гистограммы
   117|   107|  — adx: направленный trend filter, volume confirm, exit-signal при падении ADX, adx_threshold
   118|   108|  — supertrend: направленный trend filter (фикс бага SELL), volume confirm при флипе | Hermes
   119|   109|| 2026-06-01 22:30 | feat | Фаза 3: Momentum/Осцилляторы — 4 стратегии улучшены
   120|   110|  — rsi_oversold: направленный trend filter, volume confirm, параметры порогов
   121|   111|  — stochastic: направленный trend filter, volume confirm, параметры k_period/oversold/overbought
   122|   112|  — rsi_ma_combo: направленный trend filter (был баг — SMA200 не использовался), volume confirm, exit при RSI=50
   123|   113|  — parabolic_sar: направленный trend filter, volume confirm при флипе SAR | Hermes
   124|   114|| 2026-06-01 22:45 | feat | Фаза 4: Breakout/Volatility — 4 стратегии улучшены
   125|   115|  — atr_breakout: направленный trend filter, volume confirm, 2-candle confirmation, параметры atr_period/multiplier
   126|   116|  — bollinger_bands: направленный trend filter, volume confirm, exit при возврате к middle, параметры bb_period/bb_std
   127|   117|  — keltner_channels: направленный trend filter (фикс бага SELL), volume confirm, параметры ema/atr/multiplier
   128|   118|  — donchian: направленный trend filter, volume confirm, exit при возврате в канал, atr filter вынесен в метод | Hermes
   129|   119|| 2026-06-01 23:00 | feat | Фаза 5: Candlestick Patterns — 3 стратегии по образу молота
   130|   120|  — engulfing: exit_target=candle_range, направленный trend filter, min_engulf_ratio параметр
   131|   121|  — doji: exit_target=candle_range, направленный trend filter, volume (doji на низком объёме), параметры threshold/min_prior
   132|   122|  — three_soldiers: exit_target=avg_candle_range, направленный trend filter, volume expand confirm | Hermes
   133|   123|| 2026-06-01 23:10 | feat | Фаза 6: Volume — OBV стратегия
   134|   124|  — obv: направленный trend filter, 2-candle confirmation, confidence через normalised OBV/volume, параметр lookback | Hermes
   135|   125|| 2026-06-01 23:20 | feat | Фаза 7: VWAP — финальная стратегия
   136|   126|  — vwap: exit_target=VWAP (mean reversion), направленный trend filter (SELL fix), volume confirm, exit при возврате к VWAP, параметр deviation_pct | Hermes
   137|   127|| 2026-06-01 23:45 | fix | Светлая тема в трейдинге — все страницы
   138|   128|  — trading_page: все PfColors.foreground/mutedForeground/surface → pc.*C (темо-зависимые)
   139|   129|  — wizard_page: _PairTile фон через cardTheme, _coinLetterBox через theme (вместо Colors.white), Divider fix, bottom sheet handle через Theme.of
   140|   130|  — run_detail_page: все цвета через pc.* (theme-aware), все build-методы получили pc
   141|   131|  — rebuild: v61 → Flutter web build (56s) | Hermes
   142|   132|
   143|   133|- _locked_pairs инициализация в __init__
   144|   134|- min_confidence фильтр (сигналы < 0.3 отсеиваются при entry)
   145|   135|- ATR-based дефолтный exit_target (entry +- ATR*2) в history и virtual_live
   146|   136|- ATR-based SL в virtual_live (выбирается более строгий между ATR-SL и фикс. %) | Hermes
   147|   137|- `feat` Фаза 2: Trend-following — 5 стратегий улучшены
   148|   138|
   149|   139|- ma_crossover: направленный trend filter (BUY/SMA, SELL/SMA), volume confirm, параметры fast/slow_period
   150|   140|- triple_ma: направленный trend filter, volume confirm, exit-signal при развале alignment, параметры period\ов | Hermes
   151|   141|- `infra` Telegram Mini App: добавил роуты в super-app proxy на :8790
   152|   142|
   153|   143|Mini App URL в BotFather: https://pfumiko.ru/telegram-mini-app.html
   154|   144|- proxy_server.py: маршруты для Mini App HTML из ~/.hermes/hermes-agent/hermes_cli/web_dist/
   155|   145|- Flutter root (/) и assets не затронуты
   156|   146|- BotFather: setChatMenuButton URL обновлён на /telegram-mini-app.html | Hermes
   157|   147|- `fix` HomePage: не показывать красную ошибку 'Не удалось загрузить профиль' для гостей
   158|   148|
   159|   149|- _loadUser(): проверяет наличие access_token ДО вызова API
   160|   150|- Если токена нет → сразу гостевой экран, без запроса к API
   161|   151|- Если API вернул ошибку → silent fail (debugPrint), а не красный SnackBar
   162|   152|- build v62 | Hermes
   163|   153|- `fix` Light theme: исправил хардкодные тёмные цвета в общих виджетах и страницах трейдинга
   164|   154|
   165|   155|- PfCard: PfColors.card/border → pc.cardC/pc.borderC
   166|   156|- PfDivider: PfColors.border → pc.borderC
   167|   157|- PfBadge: PfColors.muted/mutedForeground → pc.mutedC/pc.mutedForegroundC
   168|   158|- PfButton: PfColors.surface/foreground/border → pc.surfaceC/pc.foregroundC/pc.borderC
   169|   159|- Trading pill tabs: Color(0xFF181A20) → pc.foregroundC
   170|   160|- Wizard progress bar: Color(0xFF181A20) → theme.colorScheme.onPrimary, PfColors.muted → pc.mutedC
   171|   161|- Wizard mode cards, notifications, toggles: isDark ? white : black → pc.mutedC/pc.borderC
   172|   162|- build v63 | Hermes
   173|   163|