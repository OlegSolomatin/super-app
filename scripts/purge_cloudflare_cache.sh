#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────
# Purge Cloudflare cache for pfumiko.ru
# ─────────────────────────────────────────────────────────
# Использование:
#   ./purge_cloudflare_cache.sh
#   ./purge_cloudflare_cache.sh --files /main.dart.js /index.html
#
# Перед первым запуском:
#   1. Создай API токен: https://dash.cloudflare.com/profile/api-tokens
#      → "Create Token" → "Purge Cache" template
#      → Permission: Zone > Cache Purge > Purge
#      → Zone Resources: pfumiko.ru
#   2. Добавь в backend/.env:
#      CLOUDFLARE_API_TOKEN=токен_сюда
#      CLOUDFLARE_ZONE_ID=айди_зоны_сюда
#
# Zone ID можно узнать:
#   - В панели Cloudflare → Overview → справа "Zone ID"
#   - Или скрипт сам получит, если есть токен и нет Zone ID
# ─────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../backend/.env"

# ── Загружаем .env ─────────────────────────────────
if [ -f "$ENV_FILE" ]; then
  set -a
  source "$ENV_FILE"
  set +a
fi

TOKEN="${CLOUDFLARE_API_TOKEN:-}"
ZONE_ID="${CLOUDFLARE_ZONE_ID:-}"

# ── Проверка токена ─────────────────────────────────
if [ -z "$TOKEN" ]; then
  echo "❌ CLOUDFLARE_API_TOKEN не найден!"
  echo ""
  echo "  1. Создай токен: https://dash.cloudflare.com/profile/api-tokens"
  echo "     → 'Create Token' → 'Purge Cache' template"
  echo "     → Permission: Zone > Cache Purge > Purge"
  echo "     → Zone Resources: Include > Specific zone > pfumiko.ru"
  echo ""
  echo "  2. Добавь в backend/.env:"
  echo "     CLOUDFLARE_API_TOKEN=токен_сюда"
  exit 1
fi

# ── Получаем Zone ID, если не задан ────────────────
if [ -z "$ZONE_ID" ]; then
  echo "🔍 Получаю Zone ID для pfumiko.ru..."
  ZONE_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    | python3 -c "
import sys, json
data = json.load(sys.stdin)
for zone in data.get('result', []):
    if zone['name'] == 'pfumiko.ru' or zone['name'].endswith('.pfumiko.ru'):
        print(zone['id'])
        break
" 2>/dev/null || echo "")

  if [ -z "$ZONE_ID" ]; then
    echo "❌ Не удалось получить Zone ID автоматически."
    echo "   Добавь вручную в backend/.env:"
    echo "   CLOUDFLARE_ZONE_ID=..."
    exit 1
  fi
  echo "✅ Zone ID: $ZONE_ID"
fi

# ── Сброс кэша ─────────────────────────────────────
PURGE_TYPE="full"
PURGE_PAYLOAD='{"purge_everything":true}'

# Если указаны конкретные файлы
if [ "${1:-}" = "--files" ] && [ $# -gt 1 ]; then
  shift
  PURGE_TYPE="files"
  # Формируем список URL
  FILES_JSON="["
  FIRST=true
  for f in "$@"; do
    if [ "$FIRST" = true ]; then
      FIRST=false
    else
      FILES_JSON+=","
    fi
    FILES_JSON+="\"https://pfumiko.ru$f\""
  done
  FILES_JSON+="]"
  PURGE_PAYLOAD="{\"files\":$FILES_JSON}"
fi

echo "🚀 Сбрасываю Cloudflare кэш ($PURGE_TYPE)..."
RESPONSE=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/purge_cache" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "$PURGE_PAYLOAD")

SUCCESS=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('success',False))" 2>/dev/null)

if [ "$SUCCESS" = "True" ]; then
  echo "✅ Кэш Cloudflare очищен!"
else
  echo "❌ Ошибка очистки кэша:"
  echo "$RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$RESPONSE"
  exit 1
fi
