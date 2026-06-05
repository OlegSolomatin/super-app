#!/usr/bin/env bash
# ═══════════════════════════════════════════
# build_and_deploy.sh — полный цикл деплоя
# ═══════════════════════════════════════════
# 1. Собирает Flutter web
# 2. Записывает в CHANGELOG
# 3. Чистит Cloudflare кэш
# 4. Коммитит и пушит в GitHub
# ═══════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR/.."
BUILD_NUMBER="${1:-}"

echo "═══════════════════════════════════════"
echo "  🚀 Build & Deploy Super-App"
echo "═══════════════════════════════════════"

# ── 1. Определяем версию ─────────────────────
cd "$PROJECT_DIR/app"

CURRENT_VERSION=$(grep 'version:' pubspec.yaml | head -1 | sed 's/version: //')
echo "📦 Текущая версия: $CURRENT_VERSION"

if [ -n "$BUILD_NUMBER" ]; then
  # Обновляем build number
  NEW_VERSION="1.0.0+$BUILD_NUMBER"
  sed -i "s/^version: .*/version: $NEW_VERSION/" pubspec.yaml
  echo "📝 Новая версия: $NEW_VERSION"
fi

# ── 2. Сборка ─────────────────────────────
echo ""
echo "🔨 Сборка Flutter web..."
export PATH="/home/oleg/flutter/bin:$PATH"
flutter build web
echo "✅ Сборка готова"

# ── 3. CHANGELOG ─────────────────────────────
echo ""
read -p "📝 Описание изменений (feat/fix/infra): " CHANGE_TYPE
read -p "📝 Сообщение: " CHANGE_MSG
bash "$SCRIPT_DIR/log.sh" "$CHANGE_TYPE" "$CHANGE_MSG"

# ── 4. Git ─────────────────────────────────
echo ""
echo "📤 Git commit & push..."
cd "$PROJECT_DIR"
git add -A
git commit -m "$CHANGE_TYPE: $CHANGE_MSG"
git push
echo "✅ Git push готов"

# ── 5. Cloudflare Purge ───────────────────
echo ""
echo "☁️  Очистка Cloudflare кэша..."
if bash "$SCRIPT_DIR/purge_cloudflare_cache.sh" 2>/dev/null; then
  echo "✅ Cloudflare кэш очищен"
else
  echo "⚠️  Cloudflare purge пропущен (нет токена или ошибка)"
  echo "   Настрой: https://dash.cloudflare.com/profile/api-tokens"
fi

echo ""
echo "═══════════════════════════════════════"
echo "  ✅ Деплой завершён!"
echo "═══════════════════════════════════════"
