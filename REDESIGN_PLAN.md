# План редизайна pfumiko.ru (super-app)

**Дата:** 2026-06-01  
**Статус:** Утверждён  
**Архитектура:** Единый скелет + тематические Skin'ы

---

## 1. Концепция

Сайт — единый продукт с общей базой (фон, карточки, типографика, навигация).
Каждый раздел получает свой **акцентный цвет** и **специфичные компоненты**.

### Три уровня системы

```
Уровень 0 — Brand (общий для всех страниц)
├── Фон: --background (Linear deep dark #0B0E11)
├── Карточки: --card / --surface (#1E2329)
├── Типографика: Inter, шкала 8 уровней
├── Отступы: 4px-base шкала
├── Скругления: xs→pill
├── Сайдбар, хедер, навигация
│
├── Уровень 1 — Section Theme (меняется по разделу)
│   ├── --primary / --primary-foreground (акцент)
│   ├── --success / --destructive
│   └── --chart-1..5
│   │
│   └── Уровень 2 — Components (специфичные разделу)
│       ├── Trading → markets-table-card, price-cell
│       ├── Music → playlist-card, player-bar
│       ├── Video → video-card
│       ├── Posts → post-card, feed
│       └── Admin → agent-card, status-indicator
```

---

## 2. Маппинг разделов → бренды-референсы

| Раздел | Референс | Акцентный цвет |
|--------|----------|----------------|
| 🏠 Главная | Linear (нейтральный) | Лаванда `#5E6AD2` |
| 📊 Трейдинг | **Binance** 🔥 | Жёлтый `#FCD535` |
| 🎵 Музыка | Spotify | Зелёный `#1DB954` |
| 🎬 Видео | YouTube/Netflix | Красный `#FF0000` |
| 📝 Посты | Medium/Notion | Серый/чёрный |
| 🤖 Агенты | Linear | Лаванда `#5E6AD2` |
| ⚙️ Настройки | Stripe | Индиго `#533AFD` |
| 🔐 Логин/Регистрация | Stripe/Vercel | Индиго `#533AFD` |

---

## 3. DESIGN.md — единый дизайн-спек

**Файл:** `~/workspace/super-app/DESIGN.md` (создаётся в Фазе 0)

Содержит:
- Полную карту токенов (light + dark)
- Типографическую шкалу (8 уровней)
- Spacing, rounded, shadows
- 30+ компонентов с token references
- Do's and Don'ts

После создания DESIGN.md все UI-решения сверяются с ним.

---

## 4. Система токенов (цвета)

### Dark theme (основная)

```dart
--background: #0B0E11        // Canvas (Binance dark)
--foreground: #EAECEF        // Body text
--card: #1E2329              // Surface card
--card-foreground: #EAECEF
--surface: #2B3139           // Elevated surface
--surface-foreground: #EAECEF
--muted: #2B3139
--muted-foreground: #707A8A
--border: #2B3139            // Hairline on dark
--input: #2B3139
--ring: var(--primary)       // Focus ring = accent
--sidebar: #010102           // Linear deep dark
--sidebar-foreground: #D0D6E0
--sidebar-hairline: #23252A
--success: #0ECB81           // Trading up
--destructive: #F6465D       // Trading down
--warning: #F0B90B
--chart-1..5: варианты
```

### Light theme (для форм/логина/транзакций)

```dart
--background: #F5F5F5
--foreground: #181A20
--card: #FFFFFF
--card-foreground: #181A20
--border: #EAECEF
--primary: #FCD535
--primary-foreground: #181A20
```

### Section Theme (меняется)

Каждый раздел определяет только:
```dart
class SectionTheme {
  final Color accent;           // primary
  final Color accentForeground; // onPrimary
  final Color? success;         // опционально
  final Color? destructive;     // опционально
  final PhosphorIconData icon;
}
```

---

## 5. Типографика

Шрифт: **Inter** (Google Fonts, open-source, близок к BinanceNova)

| Токен | Размер | Weight | Применение |
|-------|--------|--------|-----------|
| display-xl | 48px | 700 | Герои |
| display-lg | 36px | 600 | Заголовки разделов |
| display-md | 28px | 600 | Заголовки страниц |
| title-lg | 20px | 600 | Заголовки карточек |
| title-md | 16px | 600 | Заголовки секций |
| body-lg | 15px | 400 | Основной текст |
| body-md | 14px | 400 | Второстепенный |
| body-sm | 13px | 400 | Мелкий текст |
| caption | 12px | 500 | Подписи, метки |
| button | 14px | 600 | Кнопки |
| number | 14px | 500 | Цены, цифры (tabular) |

Цифры в трейдинге: **JetBrains Mono** (как fallback для BinancePlex).

---

## 6. Spacing / Rounded / Elevation

### Spacing (4px base)
```
xxs:4  xs:8  sm:12  md:16  lg:24  xl:32  xxl:48  section:80
```

### Rounded
```
xs:2  sm:4  md:6  lg:8  xl:12  2xl:16  pill:9999
```

### Elevation
- **Flat** — без тени, только hairline (основной режим)
- **Hairline** — 1px `--border` (стандарт для всех карточек)
- **Focus ring** — 2px `--ring` (только для input/button фокуса)
- **Никаких теней и glassmorphism** — цветовой контраст вместо теней

---

## 7. Компоненты (shared/widgets/)

### 7.1 ButtonKit (`v2_button.dart`)
```dart
PfButton(
  variant: 'primary' | 'secondary' | 'ghost' | 'outline' | 'destructive' | 'link',
  size: 'sm' | 'md' | 'lg' | 'pill',
  icon: PhosphorIconData?,
  iconPosition: 'start' | 'end',
)
```

### 7.2 Card (`pf_card.dart`)
```dart
PfCard(
  variant: 'default' | 'elevated' | 'trading',
  header: Widget?,
  footer: Widget?,
  padding: 'sm' | 'md' | 'lg',
)
```

### 7.3 Badge (`pf_badge.dart`)
```dart
PfBadge(
  variant: 'default' | 'success' | 'warning' | 'destructive' | 'info',
  size: 'sm' | 'md',
)
```

### 7.4 Separator (`pf_separator.dart`)
```dart
PfDivider()  // — вместо Container(height:1, color:...)
```

### 7.5 Skeleton (`pf_skeleton.dart`)
```dart
PfSkeleton(width, height, shape: 'rect' | 'circle' | 'text')
```

### 7.6 Avatar (`pf_avatar.dart`)
```dart
PfAvatar(imageUrl, initials, size: 24|32|40)
```

### 7.7 DashboardTile v2 — редизайн
- ❌ Убрать glassmorphism (BackdropFilter, blur, sigma)
- ❌ Убрать boxShadow у карточек
- ✅ Плоский фон `--card`
- ✅ Hairline бордер `--border`
- ✅ Цветной круг иконки (без blur, flat gradient)
- ✅ Pulse-анимация только у admin-плитки (тонкая)

### 7.8 AdaptiveScaffold — редизайн
- ✅ Сайдбар: Linear-стиль `--sidebar: #010102`
- ✅ Активный пункт: лавандовый индикатор слева
- ✅ Avatar + username в footer сайдбара
- ✅ Высота топ-бара 64px
- ✅ Никаких разделителей между пунктами меню

---

## 8. Страницы — редизайн

### 8.1 Login / Register
- Карточка `--card` по центру
- Лого + заголовок сверху
- Инпуты 40px, hairline-бордер
- Кнопка `pill variant="primary"`
- Светлая тема (transactional стиль)
- Background: `--background: #F5F5F5`
- Акцент: индиго `#533AFD` (Stripe)

### 8.2 Home (Dashboard)
- Заголовок `display-md` "Панель управления"
- Сетка плиток: 2 колонки mobile, 4 desktop
- Плитки: плоские, hairline, цветной круг иконки
- Admin-плитка: чуть ярче border + тонкая подсветка
- Акцент: лаванда `#5E6AD2`

### 8.3 TradingPage
- Pill-табы (Active / History) как у Binance markets-switcher
- Таблица markets-table-card:
  - Строки с hairline-разделителями
  - Стратегия → Badge
  - PnL → success/destructive цвет
  - Pair → JetBrains Mono
- Кнопка "Новый запуск": pill `button-primary` (жёлтый)
- Акцент: жёлтый `#FCD535`

### 8.4 WizardPage
- Степпер: сайдбар слева с этапами
- Контент: Card с hairline
- Навигация: Back/Next внизу
- Акцент: жёлтый `#FCD535`

### 8.5 RunDetailPage
- Хедер: стратегия + Pair (mono) + статус Badge
- Статистика: 4 stat-callout (цифра + подпись)
- Таблица сделок: как markets-table-card
- PnL → success/destructive
- Акцент: жёлтый `#FCD535`

### 8.6 AdminAgentsPage (Linear-стиль)
- Deep dark: canvas `#010102`, card `#0F1011`
- Заголовок + кол-во активных
- Сетка агентов: cards c hairline `#23252A`
- Статус: точка working=green, idle=muted
- Токены: тонкий прогресс-бар 4px height
- Акцент: лаванда `#5E6AD2`

### 8.7 BrainPage
- Карточки с hairline
- Статусы заметок — Badge
- Фильтр по статусу — ToggleGroup
- Поиск — search-input-on-dark

### 8.8 DeepSeekBalancePage
- stat-callout стиль (большая цифра + подпись)
- Прогресс использования (линейный, тонкий)

### 8.9 SettingsPage
- Секции: FieldSet + FieldLegend
- Поля: FieldGroup + Field
- Разделители: Separator
- Кнопки сохранения: pill `button-primary`
- Акцент: индиго `#533AFD` (Stripe)

---

## 9. Файловая структура (изменения)

```
lib/
├── core/
│   ├── theme.dart            ← ПОЛНЫЙ ПЕРЕПИСАТЬ
│   ├── section_theme.dart    ← НОВЫЙ (SectionTheme модель)
│   └── theme_provider.dart   ← ОБНОВИТЬ (учитывать секции)
├── shared/
│   ├── tokens/
│   │   ├── pf_colors.dart    ← НОВЫЙ (цветовые константы)
│   │   ├── pf_typography.dart← НОВЫЙ (типографика)
│   │   ├── pf_spacing.dart   ← НОВЫЙ (отступы)
│   │   └── pf_radius.dart    ← НОВЫЙ (скругления)
│   └── widgets/
│       ├── adaptive_scaffold.dart  ← РЕДИЗАЙН
│       ├── dashboard_tile.dart     ← ПОЛНЫЙ ПЕРЕПИСАТЬ
│       ├── v2_button.dart          ← НОВЫЙ
│       ├── pf_card.dart            ← НОВЫЙ
│       ├── pf_badge.dart           ← НОВЫЙ
│       ├── pf_separator.dart       ← НОВЫЙ
│       ├── pf_skeleton.dart        ← НОВЫЙ
│       └── pf_avatar.dart          ← НОВЫЙ
├── features/
│   ├── auth/presentation/
│   │   ├── login_page.dart         ← РЕДИЗАЙН
│   │   └── register_page.dart      ← РЕДИЗАЙН
│   ├── home/presentation/
│   │   └── home_page.dart          ← РЕДИЗАЙН
│   ├── trading/presentation/
│   │   ├── trading_page.dart       ← РЕДИЗАЙН
│   │   ├── wizard_page.dart        ← РЕДИЗАЙН
│   │   └── run_detail_page.dart    ← РЕДИЗАЙН
│   ├── admin/presentation/
│   │   ├── agents_page.dart        ← РЕДИЗАЙН
│   │   ├── brain_page.dart         ← РЕДИЗАЙН
│   │   └── deepseek_balance_page.dart ← РЕДИЗАЙН
│   └── settings/presentation/
│       └── settings_page.dart      ← РЕДИЗАЙН
├── CHANGELOG.md              ← ОБНОВЛЯТЬ ПОСЛЕ КАЖДОЙ ФАЗЫ
├── DESIGN.md                 ← НОВЫЙ (Фаза 0)
└── REDESIGN_PLAN.md          ← ЭТОТ ФАЙЛ
```

---

## 10. ORDER выполнения (фазы)

### Фаза 0 — Фундамент
- [ ] Создать `DESIGN.md` — полный дизайн-спек проекта
- [ ] Создать `tokens/` — pf_colors, pf_typography, pf_spacing, pf_radius
- [ ] Создать `section_theme.dart` — модель SectionTheme
- [ ] Переписать `theme.dart` — через токены + section accent
- [ ] Обновить `theme_provider.dart`
- [ ] ✅ CHANGELOG.md + коммит

### Фаза 1 — Базовые компоненты
- [ ] `pf_card.dart` — Card с hairline variant
- [ ] `pf_badge.dart` — Badge с variant'ами
- [ ] `pf_separator.dart` — Divider компонент
- [ ] `pf_skeleton.dart` — Skeleton для загрузки
- [ ] `pf_avatar.dart` — Avatar с fallback
- [ ] `v2_button.dart` — ButtonKit с variant/size/icon
- [ ] ✅ CHANGELOG.md + коммит

### Фаза 2 — Навигация и плитки
- [ ] `adaptive_scaffold.dart` — редизайн сайдбара (Linear)
- [ ] `dashboard_tile.dart` — полный редизайн (glassmorphism → flat)
- [ ] `home_page.dart` — редизайн главной
- [ ] ✅ CHANGELOG.md + коммит

### Фаза 3 — Страницы (по приоритету)
- [ ] TradingPage — редизайн (pill-табы, markets-table)
- [ ] WizardPage — редизайн (степпер-сайдбар, Card)
- [ ] RunDetailPage — редизайн (stat-callout, trading up/down)
- [ ] ✅ CHANGELOG.md + коммит

### Фаза 4 — Админка и остальное
- [ ] LoginPage — редизайн (светлая тема, карточка)
- [ ] RegisterPage — редизайн
- [ ] AdminAgentsPage — редизайн (Linear deep dark)
- [ ] BrainPage — редизайн
- [ ] DeepSeekBalancePage — редизайн
- [ ] SettingsPage — редизайн
- [ ] ✅ CHANGELOG.md + коммит

### Фаза 5 — Build и deploy
- [ ] Flutter build web --release
- [ ] Proxy restart
- [ ] Проверка на мобильном (Telegram) + десктоп (инкогнито)
- [ ] ✅ CHANGELOG.md + коммит

---

## 11. Технические решения

### Как работает Section Theme
```dart
// При переходе на страницу раздела:
context.read<ThemeProvider>().setSection(SectionTheme.trading());

// Внутри AppTheme:
ThemeData appTheme = baseDark.copyWith(
  colorScheme: baseDark.colorScheme.copyWith(
    primary: section.accent,
    onPrimary: section.accentForeground,
  ),
  elevatedButtonTheme: _buildButtonTheme(section.accent),
);
```

### Что НЕ меняется между разделами
- Scaffold background (`--background`)
- Card theme (`--card`, radius)
- Text theme
- Input decoration (кроме focus-rings)
- Navigation (sidebar, header)
- AppBar

### Что меняется между разделами
- `primary` / `primary-foreground`
- Focus ring color
- Button theme
- Специфичные компоненты раздела

---

## 12. Принципы (Do's and Don'ts)

### Do
- ✅ Единый сайдбар для навигации между разделами
- ✅ Акцентный цвет раздела — только для CTA, focus ring, активных состояний
- ✅ Все карточки через hairline, не через тени
- ✅ JetBrains Mono для цен и цифр в трейдинге
- ✅ Inter для всего остального текста
- ✅ Badge для статусов вместо styled Container+Text
- ✅ Separator для разделителей вместо raw Container(height:1)

### Don't
- ❌ Glassmorphism (BackdropFilter, blur) — устарел
- ❌ Тени на карточках — плоский цветовой контраст
- ❌ Raw цвета в виджетах — только через токены
- ❌ `dark:` переопределения — семантические токены
- ❌ Кастомные Container для статусов — Badge
- ❌ Разные стили сайдбара на разных страницах
