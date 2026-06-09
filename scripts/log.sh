#!/bin/bash
# ═══════════════════════════════════════════
# log.sh — быстрая запись в CHANGELOG
# ═══════════════════════════════════════════
# Использование:
#   ./log.sh agent "coder: сменил модель"
#   ./log.sh feat "добавлен экран логина"
#   ./log.sh fix "починил сборку"
#   ./log.sh infra "обновлён pipeline до v5"
#   ./log.sh docs "написал ARCHITECTURE.md"
# ═══════════════════════════════════════════

TYPE="$1"
MESSAGE="$2"
AUTHOR="${3:-Hermes}"

if [ -z "$TYPE" ] || [ -z "$MESSAGE" ]; then
    echo "Использование: $0 <тип> <сообщение> [автор]"
    echo "Типы: agent, feat, fix, infra, docs"
    exit 1
fi

CHANGELOG="$(cd "$(dirname "$0")/.." && pwd)/CHANGELOG.md"
DATE=$(date '+%Y-%m-%d %H:%M')
ENTRY="- \`$TYPE\` $MESSAGE | $AUTHOR"

# Добавляем запись после заголовков
sed -i "/^---$/a $ENTRY" "$CHANGELOG" 2>/dev/null || echo "$ENTRY" >> "$CHANGELOG"

echo "✅ Записано в CHANGELOG: $TYPE — $MESSAGE"