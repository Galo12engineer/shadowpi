#!/bin/bash
# Stop all services

echo "⏹️  Остановка всех сервисов..."

sudo systemctl stop hostapd
sudo systemctl stop dnsmasq
sudo systemctl stop v2raya
sudo systemctl stop openvpn-windscribe
sudo systemctl stop tor 2>/dev/null || true

echo "✅ Все сервисы остановлены"
