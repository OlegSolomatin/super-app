#!/bin/bash
# Start the SignalNotifier background service.
# Listens to Redis pub/sub and sends Telegram notifications.
set -e

cd /home/oleg/workspace/super-app/backend
PYTHONPATH=$PWD nohup python3 -c "
import logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(name)s: %(message)s',
)
from app.services.signals.notification_bot import SignalNotifier
import asyncio

async def main():
    n = SignalNotifier()
    n._running = True
    await n.run_forever()

try:
    asyncio.run(main())
except KeyboardInterrupt:
    pass
" > /tmp/signal_notifier.log 2>&1 &

PID=$!
echo "SignalNotifier started (PID: $PID)"
echo "Logs: tail -f /tmp/signal_notifier.log"
echo "$PID" > /tmp/signal_notifier.pid
