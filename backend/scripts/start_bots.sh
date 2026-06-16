#!/bin/bash
# ============================================================
# Стартовый скрипт ВСЕХ ботов/демонов платформы
# Вызывается из start_all.sh (шаг 8/8) или отдельно
#
# Порядок: Parser → Mapper → Notifier → Coder_PRO
# ============================================================
set +e

LOG="$HOME/bots_startup.log"
echo "" > "$LOG"
exec > >(tee -a "$LOG") 2>&1

echo "╔══════════════════════════════════════════╗"
echo "║  Bot Daemons Startup  $(date '+%d.%m.%Y %H:%M')         ║"
echo "╚══════════════════════════════════════════╝"
echo ""

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

ok()   { echo -e "  ${GREEN}[ OK ]${NC} $1"; }
fail() { echo -e "  ${RED}[FAIL]${NC} $1"; }
warn() { echo -e "  ${YELLOW}[WARN]${NC} $1"; }
step() { echo -e "\n── ${CYAN}$1${NC} ──"; }

cd /home/oleg/workspace/super-app/backend
export PYTHONPATH=$PWD

# ═══════════════════════════════════════════
step "1/4  Signal Parser (parse_telegram_signals)"
# ═══════════════════════════════════════════
# Парсит Telegram каналы скринеров раз в 5 сек
# Сохраняет в БД → Redis pub/sub channel:signal:new
if pgrep -f "parse_telegram_signals.*daemon" >/dev/null 2>&1; then
    ok "Parser уже запущен"
else
    echo "    Стартую Signal Parser..."
    nohup /home/oleg/.hermes/hermes-agent/venv/bin/python scripts/parse_telegram_signals.py \
        --daemon >> /tmp/signal_parser.log 2>&1 &
    PARSER_PID=$!
    sleep 3
    if pgrep -f "parse_telegram_signals.*daemon" >/dev/null 2>&1; then
        ok "Parser запущен (pid $PARSER_PID)"
    else
        fail "Parser не стартовал — проверь /tmp/signal_parser.log"
    fi
fi

# ═══════════════════════════════════════════
step "2/4  Signal Mapper (map_signals_daemon)"
# ═══════════════════════════════════════════
# Слушает Redis channel:signal:new → классифицирует через LLM
# Публикует channel:signal:mapped
if pgrep -f "map_signals_daemon.*run" >/dev/null 2>&1 || pgrep -f "SignalMapperDaemon" >/dev/null 2>&1; then
    ok "Mapper уже запущен"
else
    echo "    Стартую Signal Mapper..."
    nohup /home/oleg/.hermes/hermes-agent/venv/bin/python -c "
import logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s [%(levelname)s] %(name)s: %(message)s')
from scripts.map_signals_daemon import run
run()
" >> /tmp/signal_mapper.log 2>&1 &
    MAPPER_PID=$!
    sleep 3
    if pgrep -f "SignalMapperDaemon" >/dev/null 2>&1; then
        ok "Mapper запущен (pid $MAPPER_PID)"
    else
        fail "Mapper не стартовал — проверь /tmp/signal_mapper.log"
    fi
fi

# ═══════════════════════════════════════════
step "3/4  Signal Notifier (notification_bot)"
# ═══════════════════════════════════════════
# Слушает Redis channel:signal:mapped → отправляет в Telegram
# Использует ВСЕ боты из БД (Trading_info, Coder_PRO и др.)
if pgrep -f "notification_bot.*run" >/dev/null 2>&1 || pgrep -f "SignalNotifier" >/dev/null 2>&1; then
    ok "Notifier уже запущен"
else
    echo "    Стартую Signal Notifier..."
    nohup /home/oleg/.hermes/hermes-agent/venv/bin/python -c "
import logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s [%(levelname)s] %(name)s: %(message)s')
from app.services.signals.notification_bot import run
run()
" >> /tmp/signal_notifier.log 2>&1 &
    NOTIFIER_PID=$!
    sleep 3
    if pgrep -f "SignalNotifier" >/dev/null 2>&1; then
        ok "Notifier запущен (pid $NOTIFIER_PID)"
    else
        fail "Notifier не стартовал — проверь /tmp/signal_notifier.log"
    fi
fi

# ═══════════════════════════════════════════
step "4/4  Health check — Redis pub/sub chain"
# ═══════════════════════════════════════════
# Проверка что пайплайн целиком работает
echo "    Проверка Redis pub/sub..."
if redis-cli ping 2>/dev/null | grep -q PONG; then
    ok "Redis доступен"

    # Проверка подписок
    echo "    Проверка подписанных каналов..."
    CLIENT_COUNT=$(redis-cli --raw client list 2>/dev/null | grep -c "pubsub" 2>/dev/null || echo "0")
    echo "      Подписок на Redis: $CLIENT_COUNT"

    # Проверка что сигналы поступали недавно
    LAST_SIGNAL=$(redis-cli lindex "signals:latest" 0 2>/dev/null | head -c 100)
    if [ -n "$LAST_SIGNAL" ]; then
        ok "Сигналы есть в Redis (последний: $(echo $LAST_SIGNAL | python3 -c 'import sys,json; d=json.load(sys.stdin); print(f\"#{d.get(\"id\",\"?\")} {d.get(\"pair\",\"?\")}\")' 2>/dev/null)")"
    else
        warn "Нет сигналов в Redis — возможно парсер ждёт новые данные"
    fi
else
    fail "Redis недоступен — пайплайн не будет работать!"
fi

# ═══════════════════════════════════════════
echo ""
echo "══════════════════════════════════════════"
echo "  ИТОГ ЗАПУСКА БОТОВ  $(date '+%H:%M:%S')"
echo "══════════════════════════════════════════"
echo ""
echo "  Порядок: Parser → Mapper → Notifier"
echo ""
echo "  Логи:"
echo "    ~/bots_startup.log        — этот лог"
echo "    /tmp/signal_parser.log    — Parser"
echo "    /tmp/signal_mapper.log    — Mapper"
echo "    /tmp/signal_notifier.log  — Notifier"
echo ""
echo "  Проверка:"
echo "    ps aux | grep parse_telegram    (Parser)"
echo "    ps aux | grep SignalMapper      (Mapper)"
echo "    ps aux | grep SignalNotifier    (Notifier)"
echo "    tail -5 /tmp/signal_notifier.log (последние отправки)"
echo ""
echo "  Для проверки всей цепочки:"
echo "    1. Появился ли сигнал в Redis?     redis-cli lindex signals:latest 0 | python3 -m json.tool"
echo "    2. Работает ли mapper?             tail -5 /tmp/signal_mapper.log"
echo "    3. Отправился ли сигнал в TG?      tail -10 /tmp/signal_notifier.log | grep 'Sent mapped'"
echo "══════════════════════════════════════════"
echo ""
