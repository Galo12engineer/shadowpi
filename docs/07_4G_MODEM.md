# 07. Поддержка USB 4G/LTE модемов

## 📱 Зачем нужен 4G модем?

USB 4G/LTE модем позволяет роутеру работать в местах где нет проводного интернета:
- 🚗 В машине, на природе, в поездках
- 🏕️ Мобильный роутер с резервным интернетом
- 📡 Fail-over (если Ethernet упал, переключиться на 4G)
- 🌍 Использовать SIM карту другой страны для VPN

## 🔌 Поддерживаемые модемы

### Протестированные модели:
- ✅ **Huawei E3372** (LTE Cat4, рекомендуется)
- ✅ **Huawei E8372** (LTE WiFi stick)
- ✅ **Huawei E3276**
- ✅ **ZTE MF823/MF833**
- ✅ **Alcatel One Touch**

### Общие поддерживаемые чипсеты:
- Qualcomm MSM
- Huawei HiSilicon
- любые с режимом CDC-ETHER или MBIM

## 📦 Установка необходимых пакетов

```bash
# Уже должно быть установлено если использовали master-install.sh
sudo apt install -y \
    modemmanager \
    usb-modeswitch \
    usb-modeswitch-data \
    mobile-broadband-provider-info \
    libqmi-utils \
    libmbim-utils \
    network-manager

# Запуск ModemManager
sudo systemctl enable ModemManager
sudo systemctl start ModemManager
```

## 🔍 Определение модема

### Шаг 1: Подключите модем к USB

```bash
# Проверьте что Pi видит устройство
lsusb

# Должно показать что-то вроде:
# Bus 001 Device 004: ID 12d1:14dc Huawei Technologies Co., Ltd.
```

### Шаг 2: Переключение режима (usb_modeswitch)

Многие модемы при подключении работают как USB storage (виртуальный CD-ROM с драйверами). Нужно переключить в режим модема:

```bash
# Автоматическое переключение (обычно работает)
sudo usb_modeswitch -v 12d1 -p 14dc -M '55534243123456780000000000000011062000000100000000000000000000'

# Или используйте конфиг файл
sudo nano /etc/usb_modeswitch.d/12d1:14dc
```

```conf
# Huawei E3372
TargetVendor=0x12d1
TargetProduct=0x14dc
MessageContent="55534243123456780000000000000011062000000100000000000000000000"
```

```bash
# Перезагрузите правила udev
sudo udevadm control --reload-rules

# Переподключите модем или перезагрузите Pi
sudo reboot
```

### Шаг 3: Проверка что модем определился

```bash
# ModemManager должен увидеть модем
mmcli -L

# Вывод:
# /org/freedesktop/ModemManager1/Modems/0 [Huawei] E3372

# Детальная информация
mmcli -m 0

# Показывает:
# - Модель
# - IMEI
# - Состояние
# - Оператора
# - Силу сигнала
```

## 🌐 Настройка соединения

### Автоматическое подключение (простой способ)

```bash
# Подключение к интернету
sudo mmcli -m 0 --simple-connect="apn=internet"

# Для разных операторов используйте разные APN:
# МТС: internet.mts.ru
# Мегафон: internet
# Билайн: internet.beeline.ru
# Tele2: internet.tele2.ru

# С логином/паролем (если нужно)
sudo mmcli -m 0 --simple-connect="apn=internet,user=username,password=pass"

# Проверка подключения
mmcli -m 0

# Интерфейс появится как wwan0 или eth1
ip addr show wwan0
```

### Ручная настройка через NetworkManager

```bash
# Создайте профиль соединения
sudo nmcli connection add \
    type gsm \
    ifname '*' \
    con-name 4G-Internet \
    apn internet

# Активируйте
sudo nmcli connection up 4G-Internet

# Проверка
nmcli connection show 4G-Internet
ip addr show wwan0
```

### Скрипт автоматического подключения

```bash
sudo nano /opt/anon-router/scripts/connect-4g.sh
```

```bash
#!/bin/bash
# Auto-connect 4G modem

set -e

echo "📱 Подключение 4G модема..."

# Ждем пока модем определится
sleep 5

# Найти модем
MODEM=$(mmcli -L | grep -oP '/org/freedesktop/ModemManager1/Modems/\d+')

if [ -z "$MODEM" ]; then
    echo "❌ Модем не найден!"
    exit 1
fi

MODEM_ID=$(echo $MODEM | grep -oP '\d+$')

echo "✅ Модем найден: ID $MODEM_ID"

# Разблокировать SIM (если нужен PIN)
# sudo mmcli -i 0 --pin=1234

# APN (измените на свой)
APN="internet"

# Подключиться
echo "🔌 Подключение к $APN..."
sudo mmcli -m $MODEM_ID --simple-connect="apn=$APN"

# Подождать подключения
sleep 10

# Проверка
if mmcli -m $MODEM_ID | grep -q "connected"; then
    echo "✅ 4G подключен!"
    
    # Получить IP
    IP=$(ip addr show wwan0 | grep 'inet ' | awk '{print $2}')
    echo "📡 IP адрес: $IP"
    
    # Сигнал
    SIGNAL=$(mmcli -m $MODEM_ID | grep "signal quality" | awk '{print $3}')
    echo "📶 Сигнал: $SIGNAL%"
else
    echo "❌ Не удалось подключиться"
    exit 1
fi
```

```bash
sudo chmod +x /opt/anon-router/scripts/connect-4g.sh

# Запуск
sudo /opt/anon-router/scripts/connect-4g.sh
```

## 🔀 Переключение между Ethernet и 4G

### Автоматический fail-over скрипт

```bash
sudo nano /opt/anon-router/scripts/wan-failover.sh
```

```bash
#!/bin/bash
# WAN Failover: Ethernet <-> 4G

PRIMARY="eth0"
BACKUP="wwan0"
CHECK_HOST="8.8.8.8"

check_connection() {
    ping -c 2 -I $1 $CHECK_HOST &>/dev/null
    return $?
}

while true; do
    if check_connection $PRIMARY; then
        # Primary работает
        if [ "$(ip route | grep default | awk '{print $5}')" != "$PRIMARY" ]; then
            echo "✅ Переключение на $PRIMARY"
            sudo ip route del default
            sudo ip route add default via $(ip route | grep $PRIMARY | grep -v default | awk '{print $1}') dev $PRIMARY
        fi
    else
        # Primary не работает, переключаемся на backup
        if [ "$(ip route | grep default | awk '{print $5}')" != "$BACKUP" ]; then
            echo "⚠️  $PRIMARY недоступен, переключение на $BACKUP"
            sudo ip route del default
            sudo ip route add default dev $BACKUP
        fi
    fi
    
    sleep 30
done
```

```bash
sudo chmod +x /opt/anon-router/scripts/wan-failover.sh

# Запуск в фоне
sudo /opt/anon-router/scripts/wan-failover.sh &
```

### systemd сервис для failover

```bash
sudo nano /etc/systemd/system/wan-failover.service
```

```ini
[Unit]
Description=WAN Failover Ethernet <-> 4G
After=network-online.target ModemManager.service

[Service]
Type=simple
ExecStart=/opt/anon-router/scripts/wan-failover.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable wan-failover
sudo systemctl start wan-failover
```

## 📊 Мониторинг модема

### Проверка сигнала

```bash
# Качество сигнала
mmcli -m 0 | grep "signal quality"

# Детальная информация
mmcli -m 0 --signal-get

# Вывод:
#   RSSI: -65 dBm (хорошо: > -70, отлично: > -50)
#   RSRQ: -10 dB
#   RSRP: -95 dBm
#   SNR: 10 dB
```

### Скрипт мониторинга

```bash
#!/bin/bash
# 4G Modem Monitor

while true; do
    clear
    echo "═══ 4G Modem Status ═══"
    
    MODEM_ID=$(mmcli -L | grep -oP '\d+$')
    
    if [ -z "$MODEM_ID" ]; then
        echo "❌ Модем не найден"
        sleep 5
        continue
    fi
    
    # Состояние
    STATE=$(mmcli -m $MODEM_ID | grep "state:" | awk '{print $2}')
    echo "Состояние: $STATE"
    
    # Оператор
    OPERATOR=$(mmcli -m $MODEM_ID | grep "operator name:" | cut -d: -f2)
    echo "Оператор:$OPERATOR"
    
    # Сигнал
    SIGNAL=$(mmcli -m $MODEM_ID | grep "signal quality:" | awk '{print $3}')
    echo "Сигнал: $SIGNAL%"
    
    # IP
    IP=$(ip addr show wwan0 2>/dev/null | grep 'inet ' | awk '{print $2}')
    echo "IP: $IP"
    
    # Статистика
    RX=$(cat /sys/class/net/wwan0/statistics/rx_bytes 2>/dev/null)
    TX=$(cat /sys/class/net/wwan0/statistics/tx_bytes 2>/dev/null)
    echo "RX: $((RX/1024/1024)) MB"
    echo "TX: $((TX/1024/1024)) MB"
    
    sleep 5
done
```

## 🔒 Интеграция с VPN

После подключения 4G, весь трафик должен идти через VPN:

```bash
# Убедитесь что VPN использует правильный интерфейс
sudo nano /etc/openvpn/client/windscribe.conf

# Добавьте:
# route-up /opt/anon-router/scripts/vpn-route-4g.sh
```

Создайте скрипт:

```bash
sudo nano /opt/anon-router/scripts/vpn-route-4g.sh
```

```bash
#!/bin/bash
# Route VPN through 4G

# Удалить старые маршруты
ip route del default dev wwan0 2>/dev/null || true

# Добавить маршрут через VPN
ip route add default via $route_vpn_gateway dev tun0

echo "✅ VPN маршрут через 4G настроен"
```

```bash
sudo chmod +x /opt/anon-router/scripts/vpn-route-4g.sh
```

## 🐛 Troubleshooting

### Модем не определяется

```bash
# Проверьте USB
lsusb

# Попробуйте другой USB порт
# USB 2.0 порты часто работают лучше для модемов

# Перезагрузите ModemManager
sudo systemctl restart ModemManager

# Логи
sudo journalctl -u ModemManager -f
```

### Не подключается к сети

```bash
# Проверьте SIM карту вставлена
mmcli -m 0 | grep "sim path"

# Проверьте баланс и активность SIM
# Попробуйте SIM в телефоне

# Проверьте APN
# Узнайте правильный APN у оператора

# Проверьте PIN код
mmcli -i 0 --pin=1234  # если SIM заблокирована PIN
```

### Медленная скорость

```bash
# Проверьте силу сигнала (должна быть > 50%)
mmcli -m 0 | grep "signal quality"

# Попробуйте переместить Pi ближе к окну
# Используйте USB удлинитель для вынесения модема

# Проверьте тип сети
mmcli -m 0 | grep "access tech"
# Ищите LTE, а не 3G/EDGE

# Принудительно LTE
mmcli -m 0 --set-allowed-modes='4g'
```

## ✅ Готово!

USB 4G/LTE модем настроен! Переходите к **08_FIREWALL.md**
