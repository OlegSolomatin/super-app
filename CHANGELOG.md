# Changelog

## 2026-06-01 — Фаза 1: Базовые UI-компоненты

- **Создан `PfCard`** — виджет карточки с hairline-бордером `--border`, variant: default/trading, опциональные header/footer
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

