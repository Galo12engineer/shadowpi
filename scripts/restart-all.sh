#!/bin/bash
# Restart all services

echo "🔄 Перезапуск всех сервисов..."

/opt/anon-router/scripts/stop-all.sh
sleep 3
/opt/anon-router/scripts/start-all.sh

echo "✅ Все сервисы перезапущены!"
