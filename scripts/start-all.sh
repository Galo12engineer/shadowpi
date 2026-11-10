#!/bin/bash
# Start all services for ShadowPi

echo "🚀 Запуск всех сервисов..."

# 1. OpenVPN
echo "▶️  Запуск OpenVPN..."
sudo systemctl start openvpn-windscribe
sleep 3

# 2. V2Ray
echo "▶️  Запуск v2rayA..."
sudo systemctl start v2raya
sleep 2

# 3. Setup V2Ray redirect rules
echo "▶️  Настройка iptables для V2Ray..."
/opt/shadowpi/scripts/setup-v2ray-redirect.sh || echo "⚠️  V2Ray redirect не включён — трафик клиентов идёт только через VPN"

# 4. WiFi Hotspot
echo "▶️  Запуск WiFi Hotspot..."
sudo systemctl start hostapd
sudo systemctl start dnsmasq
sleep 2

# 5. Check statuses
echo ""
echo "📊 Статус сервисов:"
echo "VPN: $(systemctl is-active openvpn-windscribe)"
echo "V2Ray: $(systemctl is-active v2raya)"
echo "WiFi: $(systemctl is-active hostapd)"

echo ""
echo "✅ Все сервисы запущены!"
echo "🔒 Проверьте ваш IP: curl ipinfo.io"
