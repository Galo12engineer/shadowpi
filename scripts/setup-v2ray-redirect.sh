#!/bin/bash
# V2Ray Transparent Proxy iptables rules
# Redirects traffic from WiFi clients to V2Ray

echo "⚙️  Настройка V2Ray transparent proxy redirect..."

# Очистить старые правила V2RAY chain
iptables -t nat -F V2RAY 2>/dev/null
iptables -t nat -X V2RAY 2>/dev/null
iptables -t mangle -F V2RAY 2>/dev/null
iptables -t mangle -X V2RAY 2>/dev/null

# Создать новую цепочку
iptables -t nat -N V2RAY
iptables -t mangle -N V2RAY

# Игнорировать локальные адреса (RFC1918)
iptables -t nat -A V2RAY -d 0.0.0.0/8 -j RETURN
iptables -t nat -A V2RAY -d 10.0.0.0/8 -j RETURN
iptables -t nat -A V2RAY -d 127.0.0.0/8 -j RET URN
iptables -t nat -A V2RAY -d 169.254.0.0/16 -j RETURN
iptables -t nat -A V2RAY -d 172.16.0.0/12 -j RETURN
iptables -t nat -A V2RAY -d 192.168.0.0/16 -j RETURN
iptables -t nat -A V2RAY -d 224.0.0.0/4 -j RETURN
iptables -t nat -A V2RAY -d 240.0.0.0/4 -j RETURN

# Игнорировать порты веб-панели и SSH
iptables -t nat -A V2RAY -p tcp --dport 22 -j RETURN      # SSH
iptables -t nat -A V2RAY -p tcp --dport 80 -j RETURN      # HTTP
iptables -t nat -A V2RAY -p tcp --dport 8080 -j RETURN    # Admin panel
iptables -t nat -A V2RAY -p tcp --dport 2017 -j RETURN    # v2rayA UI
iptables -t nat -A V2RAY -p tcp --dport 443 -j RETURN     # HTTPS

# Перенаправить весь остальной TCP трафик на V2Ray (порт 12345)
iptables -t nat -A V2RAY -p tcp -j REDIRECT --to-ports 12345

# Применить цепочку V2RAY к трафику от WiFi клиентов
iptables -t nat -A PREROUTING -i wlan0 -p tcp -j V2RAY

# UDP (опционально, если V2Ray настроен на UDP)
# iptables -t mangle -A V2RAY -p udp -j TPROXY --on-port 12345 --tproxy-mark 1
# iptables -t mangle -A PREROUTING -i wlan0 -p udp -j V2RAY

echo "✅ V2Ray iptables redirect rules applied"
echo ""
echo "Проверка правил:"
iptables -t nat -L V2RAY -n -v --line-numbers
