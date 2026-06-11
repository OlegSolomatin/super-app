#!/bin/bash
# Stop the SignalNotifier background service.
if [ -f /tmp/signal_notifier.pid ]; then
    PID=$(cat /tmp/signal_notifier.pid)
    kill "$PID" 2>/dev/null && echo "SignalNotifier (PID: $PID) stopped" || echo "Process $PID not found"
    rm -f /tmp/signal_notifier.pid
else
    echo "No PID file found. Try: pkill -f notification_bot"
fi
