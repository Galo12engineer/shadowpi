#!/bin/bash
# Restart all services. Exit code: 0 only if both the stop and the start succeeded.

rc=0
echo "🔄 Перезапуск всех сервисов..."

/opt/shadowpi/scripts/stop-all.sh || rc=1
sleep 3
/opt/shadowpi/scripts/start-all.sh || rc=1

if [ $rc -ne 0 ]; then
    echo "❌ Перезапуск завершился с ошибками" >&2
    exit 1
fi
echo "✅ Все сервисы перезапущены!"
