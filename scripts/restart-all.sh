#!/bin/bash
# Restart all services

echo "🔄 Перезапуск всех сервисов..."

/opt/shadowpi/scripts/stop-all.sh
sleep 3
/opt/shadowpi/scripts/start-all.sh

echo "✅ Все сервисы перезапущены!"
