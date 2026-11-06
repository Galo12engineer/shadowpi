#!/bin/bash

###############################################################################
# SHADOWPI - WAN SWITCHING SCRIPT
# Переключение между Ethernet и USB модемом
###############################################################################

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
print_success() { echo -e "${GREEN}✅ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
print_error() { echo -e "${RED}❌ $1${NC}"; }

LOG_FILE="/var/log/shadowpi/wan.log"
WAN_STATUS_FILE="/opt/shadowpi/status/wan-status.json"
CURRENT_WAN_FILE="/opt/shadowpi/status/current-wan.txt"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

###############################################################################
# Определение доступных WAN интерфейсов
###############################################################################

detect_wan_interfaces() {
    print_info "Поиск WAN интерфейсов..."
    
    WAN_INTERFACES=()
    WAN_DETAILS=()
    
    # Ethernet (eth0)
    if ip link show eth0 &>/dev/null; then
        ETH_STATUS=$(cat /sys/class/net/eth0/operstate 2>/dev/null)
        ETH_IP=$(ip -4 addr show eth0 2>/dev/null | grep -oP 'inet \K[\d.]+')
        WAN_INTERFACES+=("eth0")
        WAN_DETAILS+=("eth0:$ETH_STATUS:$ETH_IP:Ethernet")
        
        if [ "$ETH_STATUS" = "up" ] && [ -n "$ETH_IP" ]; then
            print_success "eth0 (Ethernet): $ETH_IP"
        else
            print_warning "eth0 (Ethernet): не подключен"
        fi
    fi
    
    # USB модем интерфейсы
    for iface in usb0 usb1 eth1 eth2 wwan0; do
        if ip link show "$iface" &>/dev/null 2>&1; then
            STATUS=$(cat /sys/class/net/$iface/operstate 2>/dev/null)
            IP=$(ip -4 addr show "$iface" 2>/dev/null | grep -oP 'inet \K[\d.]+')
            WAN_INTERFACES+=("$iface")
            WAN_DETAILS+=("$iface:$STATUS:$IP:USB Modem")
            
            if [ "$STATUS" = "up" ] && [ -n "$IP" ]; then
                print_success "$iface (USB Modem): $IP"
            else
                print_warning "$iface (USB Modem): не подключен"
            fi
        fi
    done
    
    # Проверяем enx* интерфейсы (USB Ethernet от модема)
    for iface in $(ls /sys/class/net/ 2>/dev/null | grep "^enx"); do
        STATUS=$(cat /sys/class/net/$iface/operstate 2>/dev/null)
        IP=$(ip -4 addr show "$iface" 2>/dev/null | grep -oP 'inet \K[\d.]+')
        WAN_INTERFACES+=("$iface")
        WAN_DETAILS+=("$iface:$STATUS:$IP:USB Modem (Ethernet)")
        
        if [ "$STATUS" = "up" ] && [ -n "$IP" ]; then
            print_success "$iface (USB Modem): $IP"
        else
            print_warning "$iface (USB Modem): обнаружен"
        fi
    done
    
    echo ""
    echo "Найдено интерфейсов: ${#WAN_INTERFACES[@]}"
}

###############################################################################
# Получение текущего WAN
###############################################################################

get_current_wan() {
    # Определяем текущий default gateway
    CURRENT_GW_IFACE=$(ip route show default 2>/dev/null | grep -oP 'dev \K\S+' | head -1)
    
    if [ -n "$CURRENT_GW_IFACE" ]; then
        echo "$CURRENT_GW_IFACE"
    elif [ -f "$CURRENT_WAN_FILE" ]; then
        cat "$CURRENT_WAN_FILE"
    else
        echo "eth0"
    fi
}

###############################################################################
# Переключение WAN
###############################################################################

switch_wan() {
    local target="$1"
    
    print_info "Переключение WAN на: $target"
    log "Switching WAN to: $target"
    
    # Проверяем существование интерфейса
    if ! ip link show "$target" &>/dev/null 2>&1; then
        print_error "Интерфейс $target не найден"
        return 1
    fi
    
    # Поднимаем интерфейс
    ip link set "$target" up
    
    # Если это USB модем, пробуем получить IP через DHCP
    if [[ "$target" == usb* ]] || [[ "$target" == enx* ]] || [[ "$target" == wwan* ]]; then
        print_info "Получение IP через DHCP для $target..."
        dhclient -r "$target" 2>/dev/null
        dhclient "$target" 2>/dev/null
    fi
    
    # Ждём получения IP
    sleep 3
    
    TARGET_IP=$(ip -4 addr show "$target" 2>/dev/null | grep -oP 'inet \K[\d.]+')
    
    if [ -z "$TARGET_IP" ]; then
        print_error "Не удалось получить IP для $target"
        return 1
    fi
    
    # Определяем gateway
    TARGET_GW=$(ip route show dev "$target" 2>/dev/null | grep -oP 'via \K[\d.]+' | head -1)
    
    if [ -z "$TARGET_GW" ]; then
        # Пробуем стандартный gateway для сети
        TARGET_GW=$(echo "$TARGET_IP" | sed 's/\.[0-9]*$/.1/')
    fi
    
    print_info "IP: $TARGET_IP, Gateway: $TARGET_GW"
    
    # Удаляем старые default routes
    ip route del default 2>/dev/null
    
    # Добавляем новый default route
    ip route add default via "$TARGET_GW" dev "$target"
    
    if [ $? -eq 0 ]; then
        print_success "WAN переключен на $target"
        
        # Сохраняем текущий WAN
        echo "$target" > "$CURRENT_WAN_FILE"
        
        # Обновляем статус
        save_wan_status "$target" "$TARGET_IP" "$TARGET_GW"
        
        # Перезапускаем VPN если активен
        if systemctl is-active --quiet openvpn-windscribe; then
            print_info "Перезапуск VPN..."
            systemctl restart openvpn-windscribe
        fi
        
        return 0
    else
        print_error "Не удалось переключить WAN"
        return 1
    fi
}

###############################################################################
# Автоматический выбор лучшего WAN
###############################################################################

auto_select_wan() {
    print_info "Автоматический выбор лучшего WAN..."
    
    detect_wan_interfaces
    
    BEST_WAN=""
    
    # Приоритет: Ethernet > USB Modem
    for detail in "${WAN_DETAILS[@]}"; do
        IFS=':' read -r iface status ip type <<< "$detail"
        
        if [ "$status" = "up" ] && [ -n "$ip" ]; then
            # Проверяем есть ли интернет
            if ping -c 1 -W 2 -I "$iface" 8.8.8.8 &>/dev/null; then
                BEST_WAN="$iface"
                print_success "Лучший WAN: $iface ($type) - $ip"
                break
            fi
        fi
    done
    
    if [ -z "$BEST_WAN" ]; then
        # Если ничего не работает, выбираем первый доступный
        for detail in "${WAN_DETAILS[@]}"; do
            IFS=':' read -r iface status ip type <<< "$detail"
            if [ -n "$ip" ]; then
                BEST_WAN="$iface"
                break
            fi
        done
    fi
    
    if [ -n "$BEST_WAN" ]; then
        switch_wan "$BEST_WAN"
    else
        print_error "Нет доступных WAN интерфейсов"
        return 1
    fi
}

###############################################################################
# Failover (автопереключение при падении)
###############################################################################

failover_check() {
    CURRENT=$(get_current_wan)
    
    # Проверяем работает ли текущий WAN
    if ! ping -c 2 -W 3 -I "$CURRENT" 8.8.8.8 &>/dev/null; then
        print_warning "Текущий WAN ($CURRENT) недоступен!"
        log "Failover triggered: $CURRENT is down"
        
        # Переключаемся на другой
        detect_wan_interfaces
        
        for detail in "${WAN_DETAILS[@]}"; do
            IFS=':' read -r iface status ip type <<< "$detail"
            
            if [ "$iface" != "$CURRENT" ] && [ "$status" = "up" ]; then
                print_info "Попытка переключения на $iface..."
                
                if switch_wan "$iface"; then
                    log "Failover successful: switched to $iface"
                    return 0
                fi
            fi
        done
        
        print_error "Failover не удался - нет доступных альтернатив"
        return 1
    else
        print_success "Текущий WAN ($CURRENT) работает"
        return 0
    fi
}

###############################################################################
# Сохранение статуса
###############################################################################

save_wan_status() {
    local iface="$1"
    local ip="$2"
    local gw="$3"
    
    mkdir -p "$(dirname $WAN_STATUS_FILE)"
    
    # Определяем тип
    local wan_type="ethernet"
    if [[ "$iface" == usb* ]] || [[ "$iface" == enx* ]] || [[ "$iface" == wwan* ]] || [[ "$iface" == eth1 ]]; then
        wan_type="modem"
    fi
    
    cat > "$WAN_STATUS_FILE" << EOF
{
    "interface": "$iface",
    "type": "$wan_type",
    "ip": "$ip",
    "gateway": "$gw",
    "timestamp": "$(date -Iseconds)"
}
EOF
    
    log "WAN status saved: $iface ($wan_type) - $ip"
}

###############################################################################
# Показать статус
###############################################################################

show_status() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  🌐 ShadowPi - Статус WAN"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    detect_wan_interfaces
    
    echo ""
    CURRENT=$(get_current_wan)
    echo -e "Текущий WAN: ${GREEN}$CURRENT${NC}"
    
    CURRENT_IP=$(ip -4 addr show "$CURRENT" 2>/dev/null | grep -oP 'inet \K[\d.]+')
    echo -e "IP адрес:    ${GREEN}$CURRENT_IP${NC}"
    echo ""
}

###############################################################################
# Использование
###############################################################################

usage() {
    echo "Использование: $0 <команда>"
    echo ""
    echo "Команды:"
    echo "  status      - Показать статус WAN интерфейсов"
    echo "  switch <if> - Переключить на указанный интерфейс"
    echo "  auto        - Автоматически выбрать лучший WAN"
    echo "  failover    - Проверить и переключить при сбое"
    echo "  ethernet    - Переключить на Ethernet (eth0)"
    echo "  modem       - Переключить на USB модем"
    echo ""
    echo "Примеры:"
    echo "  $0 status"
    echo "  $0 switch eth0"
    echo "  $0 switch usb0"
    echo "  $0 modem"
}

###############################################################################
# Main
###############################################################################

mkdir -p /var/log/shadowpi
mkdir -p /opt/shadowpi/status

case "${1:-status}" in
    status)
        show_status
        ;;
    switch)
        if [ -z "$2" ]; then
            print_error "Укажите интерфейс: $0 switch <interface>"
            exit 1
        fi
        switch_wan "$2"
        ;;
    auto)
        auto_select_wan
        ;;
    failover)
        failover_check
        ;;
    ethernet|eth|eth0)
        switch_wan "eth0"
        ;;
    modem|usb)
        # Ищем интерфейс модема
        detect_wan_interfaces
        MODEM_IF=""
        for detail in "${WAN_DETAILS[@]}"; do
            IFS=':' read -r iface status ip type <<< "$detail"
            if [[ "$type" == *"Modem"* ]] || [[ "$type" == *"USB"* ]]; then
                MODEM_IF="$iface"
                break
            fi
        done
        
        if [ -n "$MODEM_IF" ]; then
            switch_wan "$MODEM_IF"
        else
            print_error "USB модем не найден"
            exit 1
        fi
        ;;
    help|--help|-h)
        usage
        ;;
    *)
        print_error "Неизвестная команда: $1"
        usage
        exit 1
        ;;
esac
