---
version: alpha
name: pfumiko-design
description: Super-app design system — единый скелет с тематическими skin'ами. База (фон, карточки, типографика, навигация) общая для всех разделов. Каждый раздел получает свой accent-цвет и специфичные компоненты.
colors:
  # Dark theme (основная)
  background: "#0B0E11"
  foreground: "#EAECEF"
  card: "#1E2329"
  card-foreground: "#EAECEF"
  surface: "#2B3139"
  surface-foreground: "#EAECEF"
  muted: "#2B3139"
  muted-foreground: "#707A8A"
  border: "#2B3139"
  input: "#2B3139"
  ring: "#FCD535"
  sidebar: "#010102"
  sidebar-foreground: "#D0D6E0"
  sidebar-hairline: "#23252A"
  success: "#0ECB81"
  destructive: "#F6465D"
  warning: "#F0B90B"

  # Light theme (транзакции, логин)
  background-light: "#F5F5F5"
  foreground-light: "#181A20"
  card-light: "#FFFFFF"
  border-light: "#EAECEF"

  # Chart colors
  chart-1: "#FCD535"
  chart-2: "#0ECB81"
  chart-3: "#5E6AD2"
  chart-4: "#F6465D"
  chart-5: "#1DB954"

  # Section accents (skin colors)
  accent-trading: "#FCD535"
  accent-admin: "#5E6AD2"
  accent-music: "#1DB954"
  accent-video: "#FF0000"
  accent-posts: "#6B7280"
  accent-settings: "#533AFD"
  accent-login: "#533AFD"
  accent-home: "#5E6AD2"

typography:
  display-xl:
    fontFamily: Inter, system-ui, -apple-system, sans-serif
    fontSize: 48px
    fontWeight: 700
    lineHeight: 1.1
    letterSpacing: -1.5px
  display-lg:
    fontFamily: Inter, system-ui, -apple-system, sans-serif
    fontSize: 36px
    fontWeight: 600
    lineHeight: 1.15
    letterSpacing: -1.0px
  display-md:
    fontFamily: Inter, system-ui, -apple-system, sans-serif
    fontSize: 28px
    fontWeight: 600
    lineHeight: 1.2
    letterSpacing: -0.5px
  title-lg:
    fontFamily: Inter, system-ui, -apple-system, sans-serif
    fontSize: 20px
    fontWeight: 600
    lineHeight: 1.3
    letterSpacing: 0px
  title-md:
    fontFamily: Inter, system-ui, -apple-system, sans-serif
    fontSize: 16px
    fontWeight: 600
    lineHeight: 1.4
    letterSpacing: 0px
  body-lg:
    fontFamily: Inter, system-ui, -apple-system, sans-serif
    fontSize: 15px
    fontWeight: 400
    lineHeight: 1.5
    letterSpacing: 0px
  body-md:
    fontFamily: Inter, system-ui, -apple-system, sans-serif
    fontSize: 14px
    fontWeight: 400
    lineHeight: 1.5
    letterSpacing: 0px
  body-sm:
    fontFamily: Inter, system-ui, -apple-system, sans-serif
    fontSize: 13px
    fontWeight: 400
    lineHeight: 1.5
    letterSpacing: 0px
  caption:
    fontFamily: Inter, system-ui, -apple-system, sans-serif
    fontSize: 12px
    fontWeight: 500
    lineHeight: 1.4
    letterSpacing: 0px
  button:
    fontFamily: Inter, system-ui, -apple-system, sans-serif
    fontSize: 14px
    fontWeight: 600
    lineHeight: 1
    letterSpacing: 0px
  number:
    fontFamily: JetBrains Mono, monospace
    fontSize: 14px
    fontWeight: 500
    lineHeight: 1.4
    letterSpacing: 0px
  number-display:
    fontFamily: JetBrains Mono, monospace
    fontSize: 40px
    fontWeight: 700
    lineHeight: 1.1
    letterSpacing: -1.0px

spacing:
  xxs: 4px
  xs: 8px
  sm: 12px
  md: 16px
  lg: 24px
  xl: 32px
  xxl: 48px
  section: 80px

rounded:
  xs: 2px
  sm: 4px
  md: 6px
  lg: 8px
  xl: 12px
  xxl: 16px
  pill: 9999px
  full: 9999px

components:
  # Buttons
  button-primary:
    backgroundColor: "{colors.ring}"
    textColor: "#181A20"
    typography: "{typography.button}"
    rounded: "{rounded.pill}"
    height: 40px
    padding: "12px 24px"
  button-secondary:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.foreground}"
    typography: "{typography.button}"
    rounded: "{rounded.lg}"
    height: 36px
    padding: "8px 16px"
  button-ghost:
    backgroundColor: transparent
    textColor: "{colors.foreground}"
    typography: "{typography.button}"
    rounded: "{rounded.lg}"
    height: 36px
    padding: "8px 16px"
  button-destructive:
    backgroundColor: "{colors.destructive}"
    textColor: "#FFFFFF"
    typography: "{typography.button}"
    rounded: "{rounded.md}"
    height: 36px
    padding: "8px 16px"
  button-outline:
    backgroundColor: transparent
    textColor: "{colors.foreground}"
    borderColor: "{colors.border}"
    typography: "{typography.button}"
    rounded: "{rounded.lg}"
    height: 36px
    padding: "8px 16px"
  button-trading-up:
    backgroundColor: "{colors.success}"
    textColor: "#FFFFFF"
    typography: "{typography.button}"
    rounded: "{rounded.md}"
    height: 32px
    padding: "6px 14px"
  button-trading-down:
    backgroundColor: "{colors.destructive}"
    textColor: "#FFFFFF"
    typography: "{typography.button}"
    rounded: "{rounded.md}"
    height: 32px
    padding: "6px 14px"
  button-pill:
    backgroundColor: "{colors.ring}"
    textColor: "#181A20"
    typography: "{typography.button}"
    rounded: "{rounded.pill}"
    height: 44px
    padding: "14px 32px"

  # Cards
  card-default:
    backgroundColor: "{colors.card}"
    rounded: "{rounded.xl}"
    padding: "{spacing.lg}"
    borderColor: "{colors.border}"
    borderWidth: 1px
  card-trading:
    backgroundColor: "{colors.card}"
    rounded: "{rounded.xl}"
    padding: "{spacing.md}"
    borderColor: "{colors.border}"
    borderWidth: 1px

  # Badge
  badge-default:
    backgroundColor: "{colors.muted}"
    textColor: "{colors.muted-foreground}"
    typography: "{typography.caption}"
    rounded: "{rounded.md}"
    padding: "2px 8px"
  badge-success:
    backgroundColor: "{colors.success}"
    textColor: "#FFFFFF"
    typography: "{typography.caption}"
    rounded: "{rounded.md}"
    padding: "2px 8px"
  badge-destructive:
    backgroundColor: "{colors.destructive}"
    textColor: "#FFFFFF"
    typography: "{typography.caption}"
    rounded: "{rounded.md}"
    padding: "2px 8px"
  badge-warning:
    backgroundColor: "{colors.warning}"
    textColor: "#181A20"
    typography: "{typography.caption}"
    rounded: "{rounded.md}"
    padding: "2px 8px"

  # Nav
  top-nav:
    backgroundColor: "{colors.background}"
    textColor: "{colors.foreground}"
    typography: "{typography.button}"
    height: 64px
  sidebar:
    backgroundColor: "{colors.sidebar}"
    textColor: "{colors.sidebar-foreground}"
    typography: "{typography.body-md}"
    width: 240px
    hairlineColor: "{colors.sidebar-hairline}"

  # Inputs
  text-input:
    backgroundColor: "{colors.background}"
    borderColor: "{colors.input}"
    textColor: "{colors.foreground}"
    typography: "{typography.body-md}"
    rounded: "{rounded.lg}"
    height: 40px
    padding: "10px 16px"
    focusRingColor: "{colors.ring}"
  search-input:
    backgroundColor: "{colors.surface}"
    borderColor: "{colors.input}"
    textColor: "{colors.foreground}"
    typography: "{typography.body-md}"
    rounded: "{rounded.lg}"
    height: 40px
    padding: "10px 16px"

  # Trading-specific
  markets-table-card:
    backgroundColor: "{colors.card}"
    rounded: "{rounded.xl}"
    padding: "{spacing.lg}"
    borderColor: "{colors.border}"
    borderWidth: 1px
  markets-row:
    backgroundColor: transparent
    padding: "12px 0"
  price-up-cell:
    backgroundColor: transparent
    textColor: "{colors.success}"
  price-down-cell:
    backgroundColor: transparent
    textColor: "{colors.destructive}"
  stat-callout:
    backgroundColor: transparent
    textColor: "{colors.foreground}"
    numberColor: "{colors.ring}"
  scan-progress-bar:
    backgroundColor: "{colors.card}"
    barColor: "{colors.success}"
    height: 4px
    rounded: "{rounded.pill}"

  # Dashboard tile
  dashboard-tile:
    backgroundColor: "{colors.card}"
    borderColor: "{colors.border}"
    rounded: "{rounded.xxl}"
    padding: "14px 16px"
    iconContainerSize: 48px
    iconGradient: true
---
# pfumiko Design System

## Overview

pfumiko — это multi-разделный super-app с **единым скелетом** и **тематическими skin'ами**. Все страницы разделяют общую базу: фон **#0B0E11** (Binance-inspired dark canvas), карточки **#1E2329**, типографику Inter, отступы с шагом 4px. Навигация (сайдбар и топ-бар) идентична на всех страницах.

Каждый раздел сайта меняет только **акцентный цвет** (primary) и, опционально, набор специфичных компонентов — trading использует markets-table и price-cell, music будет использовать playlist-card и player-bar.

Дизайн следует принципам:
- **Flat + hairline** — плоские поверхности, разделённые 1px границами. Никаких теней и glassmorphism.
- **Один акцент** — у каждого раздела один accent-цвет, который несёт все CTA, focus ring и активные состояния.
- **Цветовой контраст вместо теней** — глубина создаётся разницей между `background`, `surface` и `card`.
- **Торговая семантика** — зелёный `#0ECB81` = вверх/прибыль, красный `#F6465D` = вниз/убыток. Только текст, не фон.

### Skin mapping

| Раздел | Акцент | Референс | Иконка |
|--------|--------|----------|--------|
| 🔐 Login/Register | Индиго `#533AFD` | Stripe (светлая тема) | key |
| 🏠 Главная | Лаванда `#5E6AD2` | Linear | house |
| 📊 Трейдинг | Жёлтый `#FCD535` | Binance | chartBar |
| 🎵 Музыка | Зелёный `#1DB954` | Spotify | musicNotes |
| 🎬 Видео | Красный `#FF0000` | YouTube | videoCamera |
| 📝 Посты | Серый `#6B7280` | Medium | fileText |
| 🤖 Агенты | Лаванда `#5E6AD2` | Linear | robot |
| ⚙️ Настройки | Индиго `#533AFD` | Stripe | gear |

## Colors

### Dark mode (default)

Базовые цвета на всех страницах. Акцентные (primary) переопределяются разделом.

| Токен | Hex | Использование |
|-------|-----|---------------|
| `--background` | `#0B0E11` | Фон страницы. Тёплый near-black — никогда не pure black. |
| `--foreground` | `#EAECEF` | Основной текст на dark canvas. Не pure white. |
| `--card` | `#1E2329` | Фон карточек. На 18 ступеней светлее background — читается как elevation. |
| `--card-foreground` | `#EAECEF` | Текст на карточках. |
| `--surface` | `#2B3139` | Поверхность второго уровня (hover, secondary buttons). |
| `--surface-foreground` | `#EAECEF` | Текст на surface. |
| `--muted` | `#2B3139` | Неактивные состояния, disabled фон. |
| `--muted-foreground` | `#707A8A` | Второстепенный текст, подписи, footer. |
| `--border` | `#2B3139` | 1px hairline-границы карточек, разделители. |
| `--input` | `#2B3139` | Границы полей ввода. |
| `--ring` | `#FCD535` | Focus ring. Меняется вместе с primary. |
| `--sidebar` | `#010102` | Сайдбар. Deepest dark — почти чёрный. |
| `--sidebar-foreground` | `#D0D6E0` | Текст сайдбара. |
| `--sidebar-hairline` | `#23252A` | Разделитель сайдбара и контента. |
| `--success` | `#0ECB81` | Trading up, успешные операции. |
| `--destructive` | `#F6465D` | Trading down, ошибки, удаление. |
| `--warning` | `#F0B90B` | Предупреждения. |

### Light mode (Login / Register / Settings)

| Токен | Hex | Использование |
|-------|-----|---------------|
| `--background-light` | `#F5F5F5` | Фон страницы. |
| `--foreground-light` | `#181A20` | Основной текст. Совпадает с Binance `ink`. |
| `--card-light` | `#FFFFFF` | Карточки. |
| `--border-light` | `#EAECEF` | Hairline-границы на светлом. |

## Typography

Система использует **Inter** для всего текста и **JetBrains Mono** для числовых данных (цены, объёмы, проценты).

### Hierarchy

| Token | Size | Weight | Line H | Letter Sp | Use |
|-------|------|--------|--------|-----------|-----|
| `display-xl` | 48px | 700 | 1.1 | -1.5px | Герои, заголовки страниц |
| `display-lg` | 36px | 600 | 1.15 | -1.0px | Заголовки разделов |
| `display-md` | 28px | 600 | 1.2 | -0.5px | Подзаголовки страниц |
| `title-lg` | 20px | 600 | 1.3 | 0 | Заголовки карточек |
| `title-md` | 16px | 600 | 1.4 | 0 | Заголовки секций внутри карточек |
| `body-lg` | 15px | 400 | 1.5 | 0 | Основной текст, абзацы |
| `body-md` | 14px | 400 | 1.5 | 0 | Второстепенный текст, описания |
| `body-sm` | 13px | 400 | 1.5 | 0 | Мелкий текст, мета-информация |
| `caption` | 12px | 500 | 1.4 | 0 | Badge, подписи кнопок, label |
| `button` | 14px | 600 | 1.0 | 0 | Все кнопки |
| `number` | 14px | 500 | 1.4 | 0 | Цены, объёмы (JetBrains Mono) |
| `number-display` | 40px | 700 | 1.1 | -1.0px | Крупные цифры (JetBrains Mono) |

### Principles

- Display sizes use 600-700 weight. Trading platform заголовки не должны быть тонкими.
- Цифры всегда в JetBrains Mono. Никогда не используй Inter для цен.
- Body text — 400 weight. Аккуратная читаемость без лишнего акцента.

## Layout

### Spacing system

- **Base unit:** 4px.
- **Токены:** `{spacing.xxs}` 4px · `{spacing.xs}` 8px · `{spacing.sm}` 12px · `{spacing.md}` 16px · `{spacing.lg}` 24px · `{spacing.xl}` 32px · `{spacing.xxl}` 48px · `{spacing.section}` 80px.
- **Section padding (vertical):** `{spacing.section}` (80px).
- **Card internal padding:** `{spacing.lg}` (24px) для контента; `{spacing.md}` (16px) для плотных списков.
- **Grid gutters:** `{spacing.lg}` (24px) между карточками.

### Grid & Container

- **Max content width:** ~1200px centered.
- **Dashboard:** ResponsiveGrid — 2 колонки mobile, 4 desktop.
- **Trading:** 8/4 split (таблица + сайдбар статистики).
- **Admin:** 3 или 4 колонки для карточек агентов.

## Elevation & Depth

| Level | Treatment | Use |
|-------|-----------|-----|
| Flat | No shadow, no border | Body sections, top nav, sidebar |
| Hairline | 1px `{colors.border}` | All cards, containers, table rows |
| Focus ring | 2px `{colors.ring}` with 1px gap | Input + button keyboard focus |

The elevation philosophy is **flat surfaces with color-block separation**. Depth comes from the contrast between `{colors.background}` and `{colors.card}` (18-step lightness jump) and `{colors.sidebar}` (deepest dark).

**No shadows. No glassmorphism. No blur.**

### Exceptions
- **Dashboard tile admin glow:** A subtle `{colors.accent-admin}` shadow at 12% opacity for the admin tile only.
- **Modal overlay:** 50% black backdrop.

## Shapes

### Border Radius Scale

| Token | Value | Use |
|-------|-------|-----|
| `{rounded.xs}` | 2px | Rare — reserved for tiny badges |
| `{rounded.sm}` | 4px | Very small inline indicators |
| `{rounded.md}` | 6px | Trading action buttons (small) |
| `{rounded.lg}` | 8px | Standard inputs, secondary buttons |
| `{rounded.xl}` | 12px | Default card radius |
| `{rounded.xxl}` | 16px | Dashboard tiles |
| `{rounded.pill}` | 9999px | Primary CTA, accent actions |

### Photography & Iconography
- Icons: Phosphor Icons Fill (PhosphorIconsFill).
- Icon container (dashboard tile): 48px circle with gradient background + icon at 26px.
- Avatar: 32px circle.

## Components

### Buttons

**`button-primary`** — The primary CTA. Accent-colored background with dark text. Pill shape, 40px tall. Used for "Create", "Start", "Save" actions.

**`button-secondary`** — Secondary action. `{colors.surface}` background, no border. 36px tall. For less emphasized actions.

**`button-ghost`** — Text-only button with hover state. Transparent background. For cancel, dismiss, tertiary actions.

**`button-destructive`** — Destructive action. `{colors.destructive}` background. For delete, stop, error-related actions.

**`button-outline`** — Border-only button. `{colors.border}` border, transparent background. For "View detail", "Open" actions.

**`button-trading-up`** — Green "Buy/Long" button. 32px tall, compact. Only in trading context.

**`button-trading-down`** — Red "Sell/Short" button. 32px tall, compact. Only in trading context.

**`button-pill`** — Large pill variant (44px). For "Sign Up", "Get Started" — homepage hero CTAs.

### Cards

**`card-default`** — The standard card container. `{colors.card}` background, 1px `{colors.border}` hairline, `{rounded.xl}` (12px), internal padding `{spacing.lg}` (24px).

**`card-trading`** — Denser card for trading tables. Same as default but padding `{spacing.md}` (16px) for more information density.

### Badge

**`badge-default`** — Neutral status. `{colors.muted}` background.
**`badge-success`** — Success/active. `{colors.success}` background.
**`badge-destructive`** — Error/failed. `{colors.destructive}` background.
**`badge-warning`** — Warning/pending. `{colors.warning}` background with dark text.

### Navigation

**`top-nav`** — 64px top bar. `{colors.background}` color. Carries page title + optional actions on the right.

**`sidebar`** — 240px side panel. `{colors.sidebar}` — deepest dark. Organized as: logo/wordmark at top, navigation items with active indicator, user profile at bottom.

### Inputs

**`text-input`** — Standard form input. 40px height, `{colors.background}` fill, 1px `{colors.input}` border, `{rounded.lg}` (8px). Focus state: 2px `{colors.ring}`.

**`search-input`** — Search field variant. Same as text-input but with `{colors.surface}` background for visual distinction.

### Trading-specific

**`markets-table-card`** — Markets table container. Card with header row, column labels, scrollable body.

**`markets-row`** — Single row with: icon + pair name | price (JetBrains Mono) | 24h change (colored) | action.

**`price-up-cell`** / **`price-down-cell`** — Color-coded price cells. Green text for up, red text for down. Small directional arrow.

**`stat-callout`** — Large number + label. Transparent background, big digit (JetBrains Mono `number-display`), subtle caption below.

**`scan-progress-bar`** — Thin horizontal bar (4px) for scanner progress. Flowing from left to right.

### Dashboard Tile

The dashboard home page tile. Flat `{colors.card}` background, 1px `{colors.border}` hairline, `{rounded.xxl}` (16px). Contains: a circular icon container with gradient, title, and subtitle. No backdrop filter, no glass effect.

## Do's and Don'ts

### Do
- Reserve the accent color for primary CTAs, focus rings, and active states. Its scarcity gives it power.
- Use flat cards with 1px hairline borders. No shadows on cards.
- Use `{colors.success}` (green) for price-up signals and `{colors.destructive}` (red) for price-down — as **text color** only, never as background fill.
- Use **JetBrains Mono** for all trading numbers (prices, volumes, PnL percentages).
- Use **Inter** for all body and display text.
- Keep the sidebar consistent across all pages — same width, same colors, same navigation order.
- Use `{spacing.section}` (80px) between major page sections.

### Don't
- Don't use glassmorphism (BackdropFilter, blur). Flatrocks.
- Don't add shadows to cards. Contrast between `background` and `card` is enough depth.
- Don't use success/destructive colors as card backgrounds — they are text-color tokens.
- Don't introduce a second accent color within a section. One accent per section.
- Don't soften display weight. `display-xl` is 700 — not 400.
- Don't hardcode colors in widgets. Always use semantic tokens.
- Don't mix font families in the same text element.
- Don't change sidebar style per page.

## Responsive Behavior

### Breakpoints

| Name | Width | Key Changes |
|------|-------|-------------|
| Mobile | < 600px | Sidebar collapses to hamburger; top bar shows burger + title; dashboard goes 1-column |
| Tablet | 600-1024px | Sidebar collapses to icon-only (64px); dashboard 2-column |
| Desktop | 1024px+ | Full sidebar (240px); dashboard 4-column; trading 8/4 split |

### Touch Targets
- Primary CTA minimum 40x40px (meets WCAG).
- Nav items have 44px+ tap area through padding.
- Compact trading buttons (32px) are acceptable for data-dense interfaces.

## Iteration Guide

1. Focus on ONE component or ONE page at a time.
2. Reference YAML tokens directly (`{colors.card}`, `{components.button-primary}`).
3. When adding a new page, first decide the section → then the accent color → then choose components.
4. Use `{token.refs}` everywhere prose mentions a color, radius, typography role, or spacing.
5. Never document hover. Document Default and Active/Pressed states only.
6. Numbers always use JetBrains Mono; copy always uses Inter.
