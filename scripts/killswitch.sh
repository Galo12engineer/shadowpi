#!/bin/bash
# Killswitch firewall using iptables
# Blocks all traffic except through VPN

set -e

echo "🔒 Активация Killswitch..."

# Flush всех существующих правил
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X

# Default policies: DROP все
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP

echo "  → Default policy: DROP"

# ═══ INPUT CHAIN ═══

# Loopback (localhost)
iptables -A INPUT -i lo -j ACCEPT

# Established/Related соединения
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# ICMP (ping)
iptables -A INPUT -p icmp -j ACCEPT

# SSH с локальной сети и WiFi
iptables -A INPUT -i wlan0 -p tcp --dport 22 -j ACCEPT
iptables -A INPUT -i eth0 -p tcp --dport 22 -j ACCEPT

# HTTP/HTTPS веб-панель (только с WiFi)
iptables -A INPUT -i wlan0 -p tcp --dport 80 -j ACCEPT
iptables -A INPUT -i wlan0 -p tcp --dport 8080 -j ACCEPT
iptables -A INPUT -i wlan0 -p tcp --dport 443 -j ACCEPT
iptables -A INPUT -i wlan0 -p tcp --dport 2017 -j ACCEPT  # v2rayA

# DNS с WiFi (dnsmasq)
iptables -A INPUT -i wlan0 -p udp --dport 53 -j ACCEPT
iptables -A INPUT -i wlan0 -p tcp --dport 53 -j ACCEPT

# DHCP с WiFi
iptables -A INPUT -i wlan0 -p udp --dport 67:68 -j ACCEPT

# VPN туннель
iptables -A INPUT -i tun0 -j ACCEPT

echo "  → INPUT rules applied"

# ═══ OUTPUT CHAIN ═══

# Loopback
iptables -A OUTPUT -o lo -j ACCEPT

# Established/Related
iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Локальный WiFi интерфейс
iptables -A OUTPUT -o wlan0 -j ACCEPT

# VPN туннель - разрешить ВСЁ
iptables -A OUTPUT -o tun0 -j ACCEPT

# DNS только через VPN
iptables -A OUTPUT -o tun0 -p udp --dport 53 -j ACCEPT
iptables -A OUTPUT -o tun0 -p tcp --dport 53 -j ACCEPT

# Разрешить VPN подключение через WAN (eth0 или wwan0)
# OpenVPN порты
iptables -A OUTPUT -o eth0 -p udp --dport 443 -j ACCEPT
iptables -A OUTPUT -o eth0 -p udp --dport 1194 -j ACCEPT
iptables -A OUTPUT -o eth0 -p udp --dport 1195 -j ACCEPT
iptables -A OUTPUT -o eth0 -p tcp --dport 443 -j ACCEPT
iptables -A OUTPUT -o eth0 -p tcp --dport 1194 -j ACCEPT

# То же для wwan0 (4G модем)
iptables -A OUTPUT -o wwan0 -p udp --dport 443 -j ACCEPT
iptables -A OUTPUT -o wwan0 -p udp --dport 1194 -j ACCEPT
iptables -A OUTPUT -o wwan0 -p tcp --dport 443 -j ACCEPT

# KILLSWITCH: Блокировать остальной трафик через eth0/wwan0
# Если VPN упал, трафик не пойдет напрямую!
iptables -A OUTPUT -o eth0 -j LOG --log-prefix "KILLSWITCH-ETH0: " --log-level 4
iptables -A OUTPUT -o eth0 -j DROP

iptables -A OUTPUT -o wwan0 -j LOG --log-prefix "KILLSWITCH-WWAN0: " --log-level 4
iptables -A OUTPUT -o wwan0 -j DROP

echo "  → OUTPUT rules applied (KILLSWITCH active)"

# ═══ FORWARD CHAIN ═══

# Established/Related
iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# WiFi → VPN туннель (РАЗРЕШИТЬ)
iptables -A FORWARD -i wlan0 -o tun0 -j ACCEPT

# VPN туннель → WiFi (обратный трафик)
iptables -A FORWARD -i tun0 -o wlan0 -j ACCEPT

# KILLSWITCH: Блокировать WiFi → eth0/wwan0 (только через VPN!)
iptables -A FORWARD -i wlan0 -o eth0 -j LOG --log-prefix "KILLSWITCH-FWD-ETH0: " --log-level 4
iptables -A FORWARD -i wlan0 -o eth0 -j DROP

iptables -A FORWARD -i wlan0 -o wwan0 -j LOG --log-prefix "KILLSWITCH-FWD-WWAN0: " --log-level 4
iptables -A FORWARD -i wlan0 -o wwan0 -j DROP

echo "  → FORWARD rules applied (WiFi → VPN only)"

# ═══ NAT ═══

# Masquerade для клиентов через VPN
iptables -t nat -A POSTROUTING -o tun0 -j MASQUERADE

echo "  → NAT rules applied"

# ═══ IPv6 БЛОКИРОВКА ═══

# Полностью отключить IPv6
ip6tables -P INPUT DROP
ip6tables -P FORWARD DROP
ip6tables -P OUTPUT DROP
ip6tables -A INPUT -i lo -j ACCEPT
ip6tables -A OUTPUT -o lo -j ACCEPT

echo "  → IPv6 blocked"

# Сохранить правила (чтобы пережили перезагрузку)
if command -v iptables-save &> /dev/null; then
    mkdir -p /etc/iptables
    iptables-save > /etc/iptables/rules.v4
    ip6tables-save > /etc/iptables/rules.v6
    echo "  → Rules saved to /etc/iptables/"
fi

echo ""
echo "✅ Killswitch активирован!"
echo ""
echo "Защита:"
echo "  • Весь трафик ТОЛЬКО через VPN (tun0)"
echo "  • Если VPN упадет - интернет заблокируется"
echo "  • IPv6 полностью отключен"
echo "  • DNS только через VPN"
echo ""
echo "Для просмотра заблокированного трафика:"
echo "  sudo dmesg | grep KILLSWITCH"
echo "  sudo journalctl -k | grep KILLSWITCH"
