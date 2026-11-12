#!/bin/bash
# ============================================================
# ShadowPi - switch between Fast and Paranoid mode
# ============================================================
# Fast:     client -> OpenVPN (-> V2Ray/Xray redirect, if configured) -> internet
# Paranoid: client -> Tor -> internet, and Tor itself goes out through the OpenVPN tunnel
#
# Paranoid mode sends every client TCP connection to Tor's TransPort and client DNS to
# Tor's DNSPort (scripts/setup-tor-redirect.sh). Other client traffic (UDP, ICMP) is
# dropped: Tor cannot carry it. If Tor is not connected, clients have no internet; they
# never fall back to the plain VPN.
#
# NOT implemented: a V2Ray/Xray hop after Tor. In Paranoid mode the V2Ray redirect is
# bypassed, and the Tor exit node sees the traffic like any other Tor exit does.
# ============================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
NC='\033[0m'

SCRIPTS=/opt/shadowpi/scripts
STATE=/opt/shadowpi/status/tor-mode
LAN_IF="${LAN_IF:-wlan0}"
TOR_LOG=/var/log/tor/notices.log
BOOTSTRAP_WAIT="${TOR_BOOTSTRAP_WAIT:-30}"   # seconds; the panel's request must not time out

ACTION=${1:-toggle}

tor_running()      { ss -ltnH 'sport = :9040' 2>/dev/null | grep -q .; }
tor_bootstrapped() { grep -q 'Bootstrapped 100%' "$TOR_LOG" 2>/dev/null; }
mode_on()          { [ -e "$STATE" ]; }

show_status() {
    echo ""
    if mode_on; then
        echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${PURPLE}  🟣 РЕЖИМ: PARANOID (клиенты → Tor)${NC}"
        echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        echo -e "  ${GREEN}Цепочка:${NC} [Клиент] → [Tor] → [Интернет]; сам Tor выходит через OpenVPN"
        echo ""
        echo -e "  • TCP клиентов идёт в Tor (TransPort 9040), DNS — в Tor (DNSPort 5353)"
        echo -e "  • Остальной трафик клиентов (UDP, ICMP) блокируется"
        echo -e "  • ISP видит VPN; VPN-провайдер видит соединение с сетью Tor"
        echo -e "  • V2Ray-хоп после Tor НЕ реализован: выходной узел Tor видит трафик как обычно"
        echo ""
        if ! tor_running; then
            echo -e "  ${RED}❌ Tor не запущен: у клиентов НЕТ интернета (обхода Tor нет)${NC}"
        elif tor_bootstrapped; then
            echo -e "  ${GREEN}✅ Tor подключён к сети${NC}"
        else
            echo -e "  ${YELLOW}⚠️  Tor ещё подключается: до этого у клиентов нет интернета${NC}"
        fi
    else
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${GREEN}  🟢 РЕЖИМ: FAST${NC}"
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        echo -e "  ${GREEN}Цепочка:${NC} [Клиент] → [OpenVPN] → [V2Ray/Proxy, если настроен] → [Интернет]"
    fi
    echo ""
}

case $ACTION in
    on|start|paranoid)
        echo -e "${PURPLE}🧅 Включение режима Paranoid (клиенты → Tor)...${NC}"

        # Tor must listen on the hotspot address: REDIRECT delivers client packets there.
        LAN_IP=$(ip -4 -o addr show "$LAN_IF" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -1)
        if [ -z "$LAN_IP" ]; then
            echo -e "${RED}❌ У интерфейса $LAN_IF нет IPv4-адреса — режим не включён${NC}" >&2
            exit 1
        fi

        sudo tee /etc/tor/torrc > /dev/null << EOF
# Tor configuration for ShadowPi Paranoid mode (written by toggle-tor.sh)
SocksPort 127.0.0.1:9050
TransPort $LAN_IP:9040
DNSPort $LAN_IP:5353
VirtualAddrNetworkIPv4 10.192.0.0/10
AutomapHostsOnResolve 1
Log notice file $TOR_LOG
EOF
        sudo mkdir -p /var/log/tor
        sudo chown debian-tor:debian-tor /var/log/tor 2>/dev/null || true
        sudo rm -f "$TOR_LOG"

        # Enabled at boot too: the redirect is re-applied by the kill switch unit, and
        # without Tor the clients would simply stay offline.
        sudo systemctl enable tor >/dev/null 2>&1 || true
        sudo systemctl restart tor
        for _ in $(seq 20); do tor_running && break; sleep 1; done
        if ! tor_running; then
            echo -e "${RED}❌ Tor не запустился — режим не включён${NC}" >&2
            sudo journalctl -u 'tor@default' -n 10 --no-pager >&2 || true
            exit 1
        fi

        sudo "$SCRIPTS/setup-tor-redirect.sh"

        echo "⏳ Tor подключается к сети (до ${BOOTSTRAP_WAIT} с)..."
        for _ in $(seq "$BOOTSTRAP_WAIT"); do tor_bootstrapped && break; sleep 1; done
        show_status
        ;;

    off|stop|fast)
        echo -e "${GREEN}⚡ Переключение на режим Fast (без Tor)...${NC}"
        sudo "$SCRIPTS/setup-tor-redirect.sh" off
        sudo systemctl stop tor 2>/dev/null || true
        sudo systemctl disable tor >/dev/null 2>&1 || true
        show_status
        ;;

    toggle)
        if mode_on; then "$0" off; else "$0" on; fi
        ;;

    status)
        show_status
        echo -e "${GREEN}Сервисы:${NC}"
        echo "  OpenVPN: $(systemctl is-active openvpn-windscribe 2>/dev/null || true)"
        echo "  Tor:     $(tor_running && echo 'запущен' || echo 'остановлен')"
        ;;

    *)
        echo "Использование: $0 {fast|paranoid|toggle|status}"
        echo ""
        echo "  fast     - 🟢 клиенты идут через VPN (и V2Ray, если настроен)"
        echo "  paranoid - 🟣 клиенты идут через Tor (Tor выходит через VPN); UDP блокируется"
        echo "  toggle   - переключить режим"
        echo "  status   - показать текущий режим"
        exit 1
        ;;
esac
