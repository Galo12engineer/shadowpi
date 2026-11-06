#!/bin/bash

###############################################################################
# SHADOWPI - MODEM AUTO-CONFIGURATION SCRIPT
# Автоматическое определение и настройка USB LTE модема
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

LOG_FILE="/var/log/shadowpi/modem.log"
STATUS_FILE="/opt/shadowpi/status/modem-status.json"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

###############################################################################
# Определение модема
###############################################################################

detect_modem() {
    print_info "Поиск USB модема..."
    log "Starting modem detection"
    
    # Список известных модемов (VendorID:ProductID)
    declare -A KNOWN_MODEMS=(
        ["12d1:14dc"]="Huawei E3372h HiLink"
        ["12d1:1f01"]="Huawei E3372h Stick"
        ["12d1:1506"]="Huawei E3372s"
        ["12d1:14db"]="Huawei E3276"
        ["12d1:1c05"]="Huawei E8372"
        ["19d2:1405"]="ZTE MF823"
        ["19d2:1225"]="ZTE MF79U"
        ["2c7c:0125"]="Quectel EC25"
        ["2c7c:0121"]="Quectel EC21"
        ["1e0e:9001"]="Qualcomm Generic"
        ["05c6:9024"]="Qualcomm 9600"
        ["05c6:9025"]="Qualcomm MDM9x07"
    )
    
    # Получаем список USB устройств
    USB_DEVICES=$(lsusb 2>/dev/null)
    
    MODEM_FOUND=""
    MODEM_NAME=""
    VENDOR_ID=""
    PRODUCT_ID=""
    
    for vid_pid in "${!KNOWN_MODEMS[@]}"; do
        if echo "$USB_DEVICES" | grep -qi "${vid_pid//:/ }"; then
            MODEM_FOUND="$vid_pid"
            MODEM_NAME="${KNOWN_MODEMS[$vid_pid]}"
            VENDOR_ID="${vid_pid%%:*}"
            PRODUCT_ID="${vid_pid##*:}"
            break
        fi
    done
    
    # Проверяем модем через ModemManager
    if [ -z "$MODEM_FOUND" ]; then
        MM_MODEM=$(mmcli -L 2>/dev/null | grep -oP '/org/freedesktop/ModemManager1/Modem/\d+')
        if [ -n "$MM_MODEM" ]; then
            MODEM_FOUND="modemmanager"
            MODEM_NAME="ModemManager detected modem"
        fi
    fi
    
    if [ -n "$MODEM_FOUND" ]; then
        print_success "Найден модем: $MODEM_NAME ($MODEM_FOUND)"
        log "Found modem: $MODEM_NAME ($MODEM_FOUND)"
        return 0
    else
        print_warning "Модем не найден"
        log "No modem found"
        return 1
    fi
}

###############################################################################
# Переключение режима (usb-modeswitch)
###############################################################################

switch_modem_mode() {
    print_info "Проверка режима модема..."
    
    # Проверяем, есть ли модем в режиме CD-ROM
    if lsusb | grep -qi "cd-rom\|mass storage"; then
        print_info "Модем в режиме CD-ROM, переключаем..."
        
        # Автопереключение через usb_modeswitch
        if [ -n "$VENDOR_ID" ] && [ -n "$PRODUCT_ID" ]; then
            usb_modeswitch -v "0x$VENDOR_ID" -p "0x$PRODUCT_ID" -W 2>/dev/null
            sleep 5
            print_success "Режим переключен"
            log "Mode switched for $VENDOR_ID:$PRODUCT_ID"
        else
            # Автоопределение
            usb_modeswitch -W 2>/dev/null
            sleep 5
        fi
    else
        print_success "Модем уже в рабочем режиме"
    fi
}

###############################################################################
# Определение сетевого интерфейса модема
###############################################################################

get_modem_interface() {
    print_info "Определение сетевого интерфейса модема..."
    
    MODEM_IFACE=""
    
    # Ждём появления интерфейса
    for i in {1..10}; do
        # Проверяем типичные интерфейсы модема
        for iface in usb0 usb1 eth1 eth2 wwan0 enx*; do
            if ip link show "$iface" &>/dev/null 2>&1; then
                MODEM_IFACE="$iface"
                break 2
            fi
        done
        
        # Проверяем интерфейсы начинающиеся с enx (USB Ethernet)
        for iface in $(ls /sys/class/net/ | grep "^enx"); do
            MODEM_IFACE="$iface"
            break 2
        done
        
        sleep 1
    done
    
    if [ -n "$MODEM_IFACE" ]; then
        print_success "Интерфейс модема: $MODEM_IFACE"
        log "Modem interface: $MODEM_IFACE"
        echo "$MODEM_IFACE"
        return 0
    else
        print_error "Интерфейс модема не найден"
        log "Modem interface not found"
        return 1
    fi
}

###############################################################################
# Настройка подключения через ModemManager
###############################################################################

setup_modemmanager() {
    print_info "Настройка через ModemManager..."
    
    # Получаем индекс модема
    MODEM_INDEX=$(mmcli -L 2>/dev/null | grep -oP 'Modem/\K\d+' | head -1)
    
    if [ -z "$MODEM_INDEX" ]; then
        print_warning "ModemManager не видит модем"
        return 1
    fi
    
    print_info "Модем #$MODEM_INDEX"
    
    # Получаем информацию о модеме
    mmcli -m "$MODEM_INDEX"
    
    # Подключаемся (простое подключение с APN)
    APN="${1:-internet}"
    
    print_info "Подключение с APN: $APN"
    mmcli -m "$MODEM_INDEX" --simple-connect="apn=$APN" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        print_success "Подключено через ModemManager"
        log "Connected via ModemManager with APN: $APN"
        return 0
    else
        print_warning "Не удалось подключиться через ModemManager"
        return 1
    fi
}

###############################################################################
# Настройка HiLink модема (DHCP)
###############################################################################

setup_hilink() {
    local iface="$1"
    
    print_info "Настройка HiLink модема ($iface)..."
    
    # HiLink модемы сами выдают IP через DHCP
    dhclient -v "$iface" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        IP=$(ip -4 addr show "$iface" | grep -oP 'inet \K[\d.]+')
        print_success "Получен IP: $IP"
        log "HiLink connected, IP: $IP"
        return 0
    else
        print_error "Не удалось получить IP"
        return 1
    fi
}

###############################################################################
# Сохранение статуса
###############################################################################

save_status() {
    local status="$1"
    local iface="$2"
    local ip="$3"
    local modem="$4"
    
    mkdir -p "$(dirname $STATUS_FILE)"
    
    cat > "$STATUS_FILE" << EOF
{
    "status": "$status",
    "interface": "$iface",
    "ip": "$ip",
    "modem": "$modem",
    "timestamp": "$(date -Iseconds)"
}
EOF
    
    log "Status saved: $status, iface: $iface, ip: $ip"
}

###############################################################################
# Основная функция
###############################################################################

main() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  🔌 ShadowPi - Настройка USB модема"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    mkdir -p /var/log/shadowpi
    log "=== Starting modem setup ==="
    
    # 1. Определяем модем
    if ! detect_modem; then
        save_status "not_found" "" "" ""
        exit 1
    fi
    
    # 2. Переключаем режим если нужно
    switch_modem_mode
    
    # 3. Определяем интерфейс
    IFACE=$(get_modem_interface)
    
    if [ -z "$IFACE" ]; then
        # Пробуем через ModemManager
        if setup_modemmanager "$1"; then
            IFACE=$(get_modem_interface)
        fi
    fi
    
    if [ -z "$IFACE" ]; then
        print_error "Не удалось определить интерфейс модема"
        save_status "error" "" "" "$MODEM_NAME"
        exit 1
    fi
    
    # 4. Настраиваем подключение
    # Huawei HiLink и подобные работают как обычный Ethernet
    if echo "$MODEM_NAME" | grep -qi "hilink\|e3372h\|e8372"; then
        setup_hilink "$IFACE"
    else
        # Для других модемов пробуем DHCP
        dhclient "$IFACE" 2>/dev/null || true
    fi
    
    # 5. Проверяем подключение
    sleep 2
    IP=$(ip -4 addr show "$IFACE" 2>/dev/null | grep -oP 'inet \K[\d.]+')
    
    if [ -n "$IP" ]; then
        print_success "Модем настроен!"
        echo ""
        echo "  Интерфейс: $IFACE"
        echo "  IP адрес:  $IP"
        echo "  Модем:     $MODEM_NAME"
        echo ""
        
        save_status "connected" "$IFACE" "$IP" "$MODEM_NAME"
        
        # Выводим интерфейс для использования в других скриптах
        echo "$IFACE" > /opt/shadowpi/status/modem-interface.txt
        
        exit 0
    else
        print_warning "Модем определён, но IP не получен"
        save_status "no_ip" "$IFACE" "" "$MODEM_NAME"
        exit 1
    fi
}

# Запуск
main "$@"
