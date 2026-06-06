 || 2026-06-06 | feat | TradingPage: индикаторы активности сигналов в карточках OB-запусков (точка + signals/мин). | Hermes
    1| || 2026-06-06 | feat | OB Run Detail: блок «Активность сигналов» (счётчики, прогресс-бар принято/отсеяно, разбивка отказов, лента сигналов). API метод getOrderBookRunStatus. build v86 | Hermes
     2|    1| || 2026-06-06 | feat | OB Engine: signal metrics в БД (7 новых полей OrderBookRun) + миграция + live-сохранение каждые 3 сек | Hermes
     3|     2|    1| || 2026-06-06 | feat | OB Engine: API эндпоинт GET /orderbook/runs/{id}/status (live-статус с метриками и сигналами). scheduler._engines для доступа к движку. | Hermes
     4|     3|     2|    1| || 2026-06-06 | feat | OB Engine: счётчики отказов сигналов (20 метрик) + Signal History Buffer (100 записей) + _reject() во всех 3 стратегиях. build v86 (backend only) | Hermes
     5|     4|     3|     2|  — 12 новых счётчиков: signals_rejected, signals_per_minute, cache_not_warm, global_stop_filtered, pairlock_filtered, has_position_filtered, rejected_spread/iceberg/confirm_ticks/no_signal/gatekeeper/wallet
     6|     5|     4|     3|  — _record_signal(): каждый return в _on_snapshot() теперь логируется в history
     7|     6|     5|     4|  — _signal_timestamps: скользящее окно для signals_per_minute
     8|     7|     6|     5|  — Strategy base: _last_rejection + _reject() для детализации причин отказа
     9|     8|     7|     6|  — Все 3 стратегии (imbalance, spread, order_flow): каждый return None вызывает _reject()
    10|     9|     8|     7|  — status property: расширен recent_signals (последние 20 записей)
    11|    10|     9|     8|  — Python import check: ✅ все 5 файлов
    12|    11|    10|     9|    1| || 2026-06-06 | feat | OB Wizard: «?» подсказки во всех 7 шагах + «Стандартные» кнопка с пресетами под каждую стратегию. OB Run Detail: «?» подсказки в настройках. build v85 | Hermes
    13|    12|    11|    10|     2|  — Все шаги визарда: заголовок + «Стандартные» + «?» (кроме сводки — только «?»)
    14|    13|    12|    11|     3|  — Параметры стратегий: «?» с пояснением каждого параметра
    15|    14|    13|    12|     4|  — Риски: «?» для SL, Trailing, Offset, MaxHold
    16|    15|    14|    13|     5|  — Точность: «?» для Confirmation Ticks, Max Spread
    17|    16|    15|    14|     6|  — Защиты: «?» для Cooldown, Auto-stop
    18|    17|    16|    15|     7|  — Три пресета «Стандартные»: Imbalance Scalping, Spread Capture, Order Flow Momentum
    19|    18|    17|    16|     8|  — RunDetail: _showHelp + _helpIcon, «?» для 10 ключей конфига
    20|    19|    18|    17|     9|  — dart analyze: 0 errors (3 pre-existing warnings)
    21|    20|    19|    18|    10|  — build v85
    22|    21|    20|    19|    11|    1|# Changelog
    23|    22|    21|    20|    12|     2|
    24|    23|    22|    21|    13|     3||| 2026-06-05 | feat | OrderBook Run Detail: сохранение конфига стратегии (config_json) в БД, отображение настроек на странице запуска. build v83 | Hermes
    25|    24|    23|    22|    14|     4||| 2026-06-05 | fix | Кнопка назад в хедере: теперь использует GoRouter.canPop() вместо Navigator.canPop(), возвращает на предыдущую страницу, а не на главную. build v84 | Hermes
    26|    25|    24|    23|    15|     5||| 2026-06-05 | fix | app_version.dart синхронизирован с pubspec.yaml (1.0.0+84), старый build показывал v82. build v84 (rebuilt) | Hermes
    27|    26|    25|    24|    16|     6|
    28|    27|    26|    25|    17|     7|| 2026-06-04 | feat | Фаза 7-8 OB System UI: TradingPage (две кнопки сввечи/ордербук) + OrderBook Wizard (7 шагов, theme-aware) | Hermes
    29|    28|    27|    26|    18|     8|| 2026-06-04 | feat | Фаза 5-6 OB System: OrderBookEngine (Exit Pipeline: custom_exit, trailing, hard stop, max hold) + run.py CLI | Hermes
    30|    29|    28|    27|    19|     9|| 2026-06-04 | feat | Фаза 0 OB System: модели данных (OrderBookSnapshot, Signal, Trade, ExitType, Cache, Config) + структура папок | Hermes
    31|    30|    29|    28|    20|    10|| 2026-06-04 | fix | Login: очистка токенов при ошибке загрузки профиля + UserProvider.clear() в logout. build v65 | Hermes
    32|    31|    30|    29|    21|    11|| 2026-06-04 | fix | BrainPage: отключена бесконечная анимация force-directed графа, AnimatedSwitcher→условный рендеринг. Чинит: белый экран + неработающую кнопку переключения табов. build v64 | Hermes
    33|    32|    31|    30|    22|    12|
    34|    33|    32|    31|    23|    13|## 2026-06-01 — 🎯 Все 7 фаз улучшения торговых стратегий завершены
    35|    34|    33|    32|    24|    14|
    36|    35|    34|    33|    25|    15|**Полный аудит и переработка 17 стратегий + engine (19 файлов)**
    37|    36|    35|    34|    26|    16|
    38|    37|    36|    35|    27|    17|**Фаза 1 — Engine (engine.py):**
    39|    38|    37|    36|    28|    18|- ATR-based SL в virtual_live режиме (ранее был только фикс.%)
    40|    39|    38|    37|    29|    19|- `_locked_pairs` инициализация (чинит `AttributeError`)
    41|    40|    39|    38|    30|    20|- `min_confidence = 0.3` фильтр при entry
    42|    41|    40|    39|    31|    21|- ATR-based дефолтный exit_target (entry ± ATR×2), если стратегия не задала свой
    43|    42|    41|    40|    32|    22|
    44|    43|    42|    41|    33|    23|**Фаза 2 — Trend-following (5 стратегий):**
    45|    44|    43|    42|    34|    24|- ma_crossover, triple_ma, macd_crossover, adx, supertrend
    46|    45|    44|    43|    35|    25|- 🐛 Критический баг: trend filter для SELL требовал `close > SMA` (SELL никогда не срабатывал)
    47|    46|    45|    44|    36|    26|- Добавлены: направленный trend filter, volume confirmation, exit-signals, параметры в __init__
    48|    47|    46|    45|    37|    27|
    49|    48|    47|    46|    38|    28|**Фаза 3 — Momentum/Осцилляторы (4 стратегии):**
    50|    49|    48|    47|    39|    29|- rsi_oversold, stochastic, rsi_ma_combo, parabolic_sar
    51|    50|    49|    48|    40|    30|- 🐛 rsi_ma_combo: trend_filter_period (SMA200) был в __init__ но НЕ ИСПОЛЬЗОВАЛСЯ в analyze()
    52|    51|    50|    49|    41|    31|- Добавлены: направленный trend filter, volume confirmation, exit-signals
    53|    52|    51|    50|    42|    32|
    54|    53|    52|    51|    43|    33|**Фаза 4 — Breakout/Volatility (4 стратегии):**
    55|    54|    53|    52|    44|    34|- atr_breakout, bollinger_bands, keltner_channels, donchian
    56|    55|    54|    53|    45|    35|- 2-candle confirmation для breakout, exit при возврате в канал/к middle
    57|    56|    55|    54|    46|    36|- ATR filter вынесен в отдельный метод (donchian)
    58|    57|    56|    55|    47|    37|
    59|    58|    57|    56|    48|    38|**Фаза 5 — Candlestick Patterns (3 стратегии) — по образу молота:**
    60|    59|    58|    57|    49|    39|- engulfing, doji, three_soldiers
    61|    60|    59|    58|    50|    40|- exit_target = candle_range (как в Hammer)
    62|    61|    60|    59|    51|    41|- Направленный trend filter, volume confirmation
    63|    62|    61|    60|    52|    42|
    64|    63|    62|    61|    53|    43|**Фаза 6 — Volume (1 стратегия):**
    65|    64|    63|    62|    54|    44|- obv: 🐛 confidence = `strength / 100000` заменён на нормализацию OBV/volume
    66|    65|    64|    63|    55|    45|- 2-candle confirmation дивергенции
    67|    66|    65|    64|    56|    46|
    68|    67|    66|    65|    57|    47|**Фаза 7 — VWAP (1 стратегия):**
    69|    68|    67|    66|    58|    48|- 🐛 SELL не имел никакого trend filter
    70|    69|    68|    67|    59|    49|- exit_target = VWAP (mean reversion), exit при возврате к VWAP
    71|    70|    69|    68|    60|    50|
    72|    71|    70|    69|    61|    51|- **Редизайн `TradingPage`** — AdaptiveScaffold с trading skin, pill-табы (Active/History), карточки запусков через PfCard + PfBadge, PnL цветом success/destructive, pair в JetBrains Mono, пустые состояния с иконкой
    73|    72|    71|    70|    62|    52|- **Редизайн `WizardPage`** — AdaptiveScaffold, степпер через Card с hairline, шаги цветом success/primary/muted, кнопки навигации через PfButton (outline/primary), setSection(trading) при входе
    74|    73|    72|    71|    63|    53|- **Редизайн `RunDetailPage`** — AdaptiveScaffold, stat-callout стиль (4 stats в ряд), информация через PfCard, сканер-прогресс с LinearProgressIndicator, торговые сделки с pair/type/PnL цветом success/destructive
    75|    74|    73|    72|    64|    54|- **Анализ:** `dart analyze` — 0 errors по всем трём файлам
    76|    75|    74|    73|    65|    55|
    77|    76|    75|    74|    66|    56|## 2026-06-01 — Фаза 2: Редизайн навигации и главной
    78|    77|    76|    75|    67|    57|
    79|    78|    77|    76|    68|    58|- **Редизайн `adaptive_scaffold.dart`** — сайдбар в стиле Linear (deep dark `#010102`, active indicator слева, avatar+username в footer), топ-бар 64px с иконкой раздела, сайдбар использует SectionTheme для skin'ов
    80|    79|    78|    77|    69|    59|- **Редизайн `dashboard_tile.dart`** — полный переезд с glassmorphism на flat + hairline: убран BackdropFilter/blur/shadows, плоский фон `--card`, 1px `--border`, иконка в flat-градиентном круге 48px
    81|    80|    79|    78|    70|    60|- **Редизайн `home_page.dart`** — убран background radial gradient, убраны старые AppTheme константы, гостевая страница через PfButton, NavDestination с PhosphorIconData + SectionTheme, setSection при навигации
    82|    81|    80|    79|    71|    61|- **Анализ:** `dart analyze` — 0 issues
    83|    82|    81|    80|    72|    62|
    84|    83|    82|    81|    73|    63|## 2026-06-01 — Фаза 1: Базовые UI-компоненты
    85|    84|    83|    82|    74|    64|- **Создан `PfButton`** — универсальная кнопка: 7 variant'ов (primary/secondary/ghost/outline/destructive/link), 7 size'ов (sm/md/lg/pill/icon-sm/icon-md/icon-lg), поддержка иконок слева/справа, loading state, expanded режим
    86|    85|    84|    83|    75|    65|- **Создан `PfBadge`** — badge с variant'ами: default/success/destructive/warning/info
    87|    86|    85|    84|    76|    66|- **Создан `PfDivider` / `PfVerticalDivider`** — системные разделители через `--border` токен
    88|    87|    86|    85|    77|    67|- **Создан `PfSkeleton`** — placeholder загрузки с пульсацией (fade in-out)
    89|    88|    87|    86|    78|    68|- **Создан `PfAvatar`** — аватар с fallback initials
    90|    89|    88|    87|    79|    69|- **Анализ:** `dart analyze` — 0 issues
    91|    90|    89|    88|    80|    70|
    92|    91|    90|    89|    81|    71|## 2026-06-01 — Фаза 0: Фундамент дизайн-системы
    93|    92|    91|    90|    82|    72|
    94|    93|    92|    91|    83|    73|- **Создан `DESIGN.md`** — полный дизайн-спек проекта по Google-спецификации: цвета, типографика, отступы, скругления, компоненты, Do's and Don'ts
    95|    94|    93|    92|    84|    74|- **Созданы токены** — `lib/shared/tokens/`:
    96|    95|    94|    93|    85|    75|  - `pf_colors.dart` — 40+ цветовых констант (dark, light, section accents, chart)
    97|    96|    95|    94|    86|    76|  - `pf_typography.dart` — 12 токенов типографики (Inter + JetBrains Mono)
    98|    97|    96|    95|    87|    77|  - `pf_spacing.dart` — 4px-base шкала отступов
    99|    98|    97|    96|    88|    78|  - `pf_radius.dart` — скругления от xs до pill
   100|    99|    98|    97|    89|    79|- **Создан `section_theme.dart`** — модель SectionTheme с 8 разделами (home, trading, admin, music, video, posts, settings, login) — каждый со своим accent-цветом и иконкой Phosphor
   101|   100|    99|    98|    90|    80|- **Переписан `theme.dart`** — ThemeData через PfColors + SectionTheme. Полностью переработаны все sub-themes (appBar, card, input, button, text, divider, dialog, snackbar, tabBar)
   102|   101|   100|    99|    91|    81|- **Обновлён `theme_provider.dart`** — добавлен `setSection()`, геттер `theme` возвращает ThemeData с учётом skin'а
   103|   102|   101|   100|    92|    82|- **Анализ:** `dart analyze` — 0 issues
   104|   103|   102|   101|    93|    83|
   105|   104|   103|   102|    94|    84|## 2026-06-01 — Утверждён план редизайна (единый скелет + skin'ы)
   106|   105|   104|   103|    95|    85|
   107|   106|   105|   104|    96|    86|- **Концепция:** единая база (фон, карточки, типографика, навигация) + тематические акцентные цвета под каждый раздел
   108|   107|   106|   105|    97|    87|- **Референсы:** Binance (трейдинг), Linear (админка), Spotify (музыка), YouTube/Netflix (видео), Stripe (настройки/логин)
   109|   108|   107|   106|    98|    88|- **Создан `REDESIGN_PLAN.md`** — полный пошаговый план редизайна всех 11 страниц
   110|   109|   108|   107|    99|    89|- **План создания `DESIGN.md`** — единый дизайн-спек для проекта (Фаза 0)
   111|   110|   109|   108|   100|    90|- **5 фаз выполнения:** Фундамент → Компоненты → Навигация → Страницы → Build
   112|   111|   110|   109|   101|    91|- **Принципы:** никакого glassmorphism, flat + hairline, семантические токены, SectionTheme
   113|   112|   111|   110|   102|    92|
   114|   113|   112|   111|   103|    93|## 2026-06-01 — Dynamic pair scanning + progress bar
   115|   114|   113|   112|   104|    94|
   116|   115|   114|   113|   105|    95|- **Dynamic pairs:** `pair_list.py` теперь загружает все USDT-пары с Binance (430+) вместо 50 хардкодных. Кэш 5 мин, fallback на хардкод.
   117|   116|   115|   114|   106|    96|- **Progress bar ETA:** на странице деталей сканера — живой прогресс-бар с кол-вом отсканированных пар, текущей парой, PnL, временем и ETA. Обновление раз в 5 сек.
   118|   117|   116|   115|   107|    97|- **API:** добавлен `/api/v1/trading/scan-progress/{run_id}` для фронта.
   119|   118|   117|   116|   108|    98|- **Dynamic TP:** для hammer/inverse_hammer — TP = entry ± (high − low) свечи-сигнала (вместо 5%). Применён ко всем 4 стратегиям.
   120|   119|   118|   117|   109|    99|- **Pair в сделках:** колонка `pair` добавлена в модель Trade, отображается в run_detail_page.
   121|   120|   119|   118|   110|   100|- **Pair-scanner стратегии:** All Pairs Hammer и All Pairs Inverse Hammer — сканируют все 430+ пар в history mode, TF ≥ 30m.
   122|   121|   120|   119|   111|   101|- **UI:** кнопка `?` вместо `!`, пресеты дат в визарде, авто-скрытие virtual/real для сканера.
   123|   122|   121|   120|   112|   102|
   124|   123|   122|   121|   113|   103|| 2026-06-01 22:00 | feat | Фаза 2: Trend-following — 5 стратегий улучшены
   125|   124|   123|   122|   114|   104|  — ma_crossover: направленный trend filter (BUY↑SMA, SELL↓SMA), volume confirm, fast/slow_period
   126|   125|   124|   123|   115|   105|  — triple_ma: направленный trend filter, volume confirm, exit-signal при развале alignment
   127|   126|   125|   124|   116|   106|  — macd_crossover: направленный trend filter, volume confirm, exit-signal при смене знака гистограммы
   128|   127|   126|   125|   117|   107|  — adx: направленный trend filter, volume confirm, exit-signal при падении ADX, adx_threshold
   129|   128|   127|   126|   118|   108|  — supertrend: направленный trend filter (фикс бага SELL), volume confirm при флипе | Hermes
   130|   129|   128|   127|   119|   109|| 2026-06-01 22:30 | feat | Фаза 3: Momentum/Осцилляторы — 4 стратегии улучшены
   131|   130|   129|   128|   120|   110|  — rsi_oversold: направленный trend filter, volume confirm, параметры порогов
   132|   131|   130|   129|   121|   111|  — stochastic: направленный trend filter, volume confirm, параметры k_period/oversold/overbought
   133|   132|   131|   130|   122|   112|  — rsi_ma_combo: направленный trend filter (был баг — SMA200 не использовался), volume confirm, exit при RSI=50
   134|   133|   132|   131|   123|   113|  — parabolic_sar: направленный trend filter, volume confirm при флипе SAR | Hermes
   135|   134|   133|   132|   124|   114|| 2026-06-01 22:45 | feat | Фаза 4: Breakout/Volatility — 4 стратегии улучшены
   136|   135|   134|   133|   125|   115|  — atr_breakout: направленный trend filter, volume confirm, 2-candle confirmation, параметры atr_period/multiplier
   137|   136|   135|   134|   126|   116|  — bollinger_bands: направленный trend filter, volume confirm, exit при возврате к middle, параметры bb_period/bb_std
   138|   137|   136|   135|   127|   117|  — keltner_channels: направленный trend filter (фикс бага SELL), volume confirm, параметры ema/atr/multiplier
   139|   138|   137|   136|   128|   118|  — donchian: направленный trend filter, volume confirm, exit при возврате в канал, atr filter вынесен в метод | Hermes
   140|   139|   138|   137|   129|   119|| 2026-06-01 23:00 | feat | Фаза 5: Candlestick Patterns — 3 стратегии по образу молота
   141|   140|   139|   138|   130|   120|  — engulfing: exit_target=candle_range, направленный trend filter, min_engulf_ratio параметр
   142|   141|   140|   139|   131|   121|  — doji: exit_target=candle_range, направленный trend filter, volume (doji на низком объёме), параметры threshold/min_prior
   143|   142|   141|   140|   132|   122|  — three_soldiers: exit_target=avg_candle_range, направленный trend filter, volume expand confirm | Hermes
   144|   143|   142|   141|   133|   123|| 2026-06-01 23:10 | feat | Фаза 6: Volume — OBV стратегия
   145|   144|   143|   142|   134|   124|  — obv: направленный trend filter, 2-candle confirmation, confidence через normalised OBV/volume, параметр lookback | Hermes
   146|   145|   144|   143|   135|   125|| 2026-06-01 23:20 | feat | Фаза 7: VWAP — финальная стратегия
   147|   146|   145|   144|   136|   126|  — vwap: exit_target=VWAP (mean reversion), направленный trend filter (SELL fix), volume confirm, exit при возврате к VWAP, параметр deviation_pct | Hermes
   148|   147|   146|   145|   137|   127|| 2026-06-01 23:45 | fix | Светлая тема в трейдинге — все страницы
   149|   148|   147|   146|   138|   128|  — trading_page: все PfColors.foreground/mutedForeground/surface → pc.*C (темо-зависимые)
   150|   149|   148|   147|   139|   129|  — wizard_page: _PairTile фон через cardTheme, _coinLetterBox через theme (вместо Colors.white), Divider fix, bottom sheet handle через Theme.of
   151|   150|   149|   148|   140|   130|  — run_detail_page: все цвета через pc.* (theme-aware), все build-методы получили pc
   152|   151|   150|   149|   141|   131|  — rebuild: v61 → Flutter web build (56s) | Hermes
   153|   152|   151|   150|   142|   132|
   154|   153|   152|   151|   143|   133|- _locked_pairs инициализация в __init__
   155|   154|   153|   152|   144|   134|- min_confidence фильтр (сигналы < 0.3 отсеиваются при entry)
   156|   155|   154|   153|   145|   135|- ATR-based дефолтный exit_target (entry +- ATR*2) в history и virtual_live
   157|   156|   155|   154|   146|   136|- ATR-based SL в virtual_live (выбирается более строгий между ATR-SL и фикс. %) | Hermes
   158|   157|   156|   155|   147|   137|- `feat` Фаза 2: Trend-following — 5 стратегий улучшены
   159|   158|   157|   156|   148|   138|
   160|   159|   158|   157|   149|   139|- ma_crossover: направленный trend filter (BUY/SMA, SELL/SMA), volume confirm, параметры fast/slow_period
   161|   160|   159|   158|   150|   140|- triple_ma: направленный trend filter, volume confirm, exit-signal при развале alignment, параметры period\ов | Hermes
   162|   161|   160|   159|   151|   141|- `infra` Telegram Mini App: добавил роуты в super-app proxy на :8790
   163|   162|   161|   160|   152|   142|
   164|   163|   162|   161|   153|   143|Mini App URL в BotFather: https://pfumiko.ru/telegram-mini-app.html
   165|   164|   163|   162|   154|   144|- proxy_server.py: маршруты для Mini App HTML из ~/.hermes/hermes-agent/hermes_cli/web_dist/
   166|   165|   164|   163|   155|   145|- Flutter root (/) и assets не затронуты
   167|   166|   165|   164|   156|   146|- BotFather: setChatMenuButton URL обновлён на /telegram-mini-app.html | Hermes
   168|   167|   166|   165|   157|   147|- `fix` HomePage: не показывать красную ошибку 'Не удалось загрузить профиль' для гостей
   169|   168|   167|   166|   158|   148|
   170|   169|   168|   167|   159|   149|- _loadUser(): проверяет наличие access_token ДО вызова API
   171|   170|   169|   168|   160|   150|- Если токена нет → сразу гостевой экран, без запроса к API
   172|   171|   170|   169|   161|   151|- Если API вернул ошибку → silent fail (debugPrint), а не красный SnackBar
   173|   172|   171|   170|   162|   152|- build v62 | Hermes
   174|   173|   172|   171|   163|   153|- `fix` Light theme: исправил хардкодные тёмные цвета в общих виджетах и страницах трейдинга
   175|   174|   173|   172|   164|   154|
   176|   175|   174|   173|   165|   155|- PfCard: PfColors.card/border → pc.cardC/pc.borderC
   177|   176|   175|   174|   166|   156|- PfDivider: PfColors.border → pc.borderC
   178|   177|   176|   175|   167|   157|- PfBadge: PfColors.muted/mutedForeground → pc.mutedC/pc.mutedForegroundC
   179|   178|   177|   176|   168|   158|- PfButton: PfColors.surface/foreground/border → pc.surfaceC/pc.foregroundC/pc.borderC
   180|   179|   178|   177|   169|   159|- Trading pill tabs: Color(0xFF181A20) → pc.foregroundC
   181|   180|   179|   178|   170|   160|- Wizard progress bar: Color(0xFF181A20) → theme.colorScheme.onPrimary, PfColors.muted → pc.mutedC
   182|   181|   180|   179|   171|   161|- Wizard mode cards, notifications, toggles: isDark ? white : black → pc.mutedC/pc.borderC
   183|   182|   181|   180|   172|   162|- build v63 | Hermes
   184|   183|   182|   181|   173|   163|