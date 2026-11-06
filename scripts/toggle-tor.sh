#!/bin/bash
# ============================================================
# ShadowPi - Toggle между режимами Fast и Paranoid
# ============================================================
# Режим Fast:     OpenVPN → V2Ray/Proxy
# Режим Paranoid: OpenVPN → Tor → V2Ray/Proxy
# ============================================================

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

TOR_STATUS=$(systemctl is-active tor 2>/dev/null || echo "inactive")
ACTION=${1:-toggle}

show_status() {
    echo ""
    if [ "$TOR_STATUS" = "active" ]; then
        echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${PURPLE}  🟣 РЕЖИМ: PARANOID (Максимальная анонимность)${NC}"
        echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        echo -e "  ${GREEN}Цепочка:${NC}"
        echo -e "  [Ты] → [OpenVPN] → [Tor] → [V2Ray/Proxy] → [Интернет]"
        echo ""
        echo -e "  ${GREEN}Что это значит:${NC}"
        echo -e "  • ISP видит: VPN трафик к Windscribe"
        echo -e "  • Windscribe видит: Tor entry node"
        echo -e "  • Tor exit видит: ${GREEN}Только шифрованный V2Ray!${NC}"
        echo -e "  • Прокси видит: Твои запросы (от Tor IP)"
        echo ""
        echo -e "  ${YELLOW}⚠️  Скорость: ~15-30 Mbps${NC}"
        echo -e "  ${GREEN}✅ Tor exit НЕ МОЖЕТ прослушать трафик!${NC}"
    else
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${GREEN}  🟢 РЕЖИМ: FAST (Быстрый)${NC}"
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        echo -e "  ${GREEN}Цепочка:${NC}"
        echo -e "  [Ты] → [OpenVPN] → [V2Ray/Proxy] → [Интернет]"
        echo ""
        echo -e "  ${GREEN}Что это значит:${NC}"
        echo -e "  • ISP видит: VPN трафик к Windscribe"
        echo -e "  • Windscribe видит: Шифрованное соединение к прокси"
        echo -e "  • Прокси видит: Твои запросы"
        echo ""
        echo -e "  ${GREEN}⚡ Скорость: ~50-100 Mbps${NC}"
    fi
    echo ""
}

case $ACTION in
    on|start|paranoid)
        echo -e "${PURPLE}🧅 Включение режима Paranoid (+ Tor)...${NC}"
        
        # Настройка Tor
        sudo tee /etc/tor/torrc > /dev/null << 'EOF'
# Tor Configuration for ShadowPi Paranoid Mode
# Трафик идёт: VPN → Tor → V2Ray/Proxy

SocksPort 9050
DNSPort 5353
TransPort 9040
VirtualAddrNetworkIPv4 10.192.0.0/10
AutomapHostsOnResolve 1

# Оптимизация производительности
CircuitBuildTimeout 30
LearnCircuitBuildTimeout 0
MaxCircuitDirtiness 600

# Логирование
Log notice file /var/log/tor/notices.log
EOF
        
        # Создание директории для логов
        sudo mkdir -p /var/log/tor
        sudo chown debian-tor:debian-tor /var/log/tor 2>/dev/null || true
        
        # Запуск Tor
        sudo systemctl start tor
        sleep 5
        
        # Проверка что Tor запустился
        if ! systemctl is-active --quiet tor; then
            echo -e "${RED}❌ Ошибка: Tor не запустился!${NC}"
            sudo journalctl -u tor -n 10 --no-pager
            exit 1
        fi
        
        TOR_STATUS="active"
        show_status
        
        # Тест Tor соединения
        echo -e "${GREEN}Проверка Tor соединения...${NC}"
        TOR_IP=$(curl -s --max-time 30 --socks5 127.0.0.1:9050 https://check.torproject.org/api/ip 2>/dev/null || echo "error")
        
        if [[ "$TOR_IP" == *"IsTor"* ]]; then
            echo -e "${GREEN}✅ Tor работает!${NC}"
            echo "$TOR_IP" | jq . 2>/dev/null || echo "$TOR_IP"
        else
            echo -e "${YELLOW}⚠️  Tor запущен, но соединение ещё устанавливается...${NC}"
            echo -e "   Подождите 30 секунд и проверьте: curl --socks5 127.0.0.1:9050 ipinfo.io"
        fi
        ;;
    
    off|stop|fast)
        echo -e "${GREEN}⚡ Переключение на режим Fast (без Tor)...${NC}"
        sudo systemctl stop tor 2>/dev/null || true
        
        TOR_STATUS="inactive"
        show_status
        ;;
    
    toggle)
        if [ "$TOR_STATUS" = "active" ]; then
            $0 off
        else
            $0 on
        fi
        ;;
    
    status)
        show_status
        
        echo -e "${GREEN}Детали сервисов:${NC}"
        echo -n "  OpenVPN: "
        systemctl is-active openvpn* 2>/dev/null || echo "не настроен"
        echo -n "  V2Ray:   "
        systemctl is-active v2raya 2>/dev/null || echo "не настроен"
        echo -n "  Tor:     "
        systemctl is-active tor 2>/dev/null || echo "выключен"
        echo ""
        
        # Показать текущий IP
        echo -e "${GREEN}Текущий IP:${NC}"
        CURRENT_IP=$(curl -s --max-time 5 ipinfo.io 2>/dev/null || echo "не удалось получить")
        echo "$CURRENT_IP" | jq -r '"  IP: \(.ip)\n  Город: \(.city)\n  Страна: \(.country)"' 2>/dev/null || echo "  $CURRENT_IP"
        ;;
    
    *)
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "  ShadowPi - Переключение режимов"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "  Использование: $0 {fast|paranoid|toggle|status}"
        echo ""
        echo "  Команды:"
        echo "    fast     - 🟢 Режим Fast: VPN → Proxy (быстрый)"
        echo "    paranoid - 🟣 Режим Paranoid: VPN → Tor → Proxy (анонимный)"
        echo "    toggle   - Переключить между режимами"
        echo "    status   - Показать текущий режим"
        echo ""
        echo "  Примеры:"
        echo "    $0 fast      # Выключить Tor, быстрый режим"
        echo "    $0 paranoid  # Включить Tor, максимальная анонимность"
        echo "    $0 toggle    # Переключить режим"
        echo ""
        exit 1
        ;;
esac
