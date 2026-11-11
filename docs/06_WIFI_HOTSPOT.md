# 06. WiFi Hotspot - Полная настройка

## 📶 Компоненты WiFi Hotspot

Для создания WiFi точки доступа используются:
- **hostapd** - превращает WiFi адаптер в Access Point
- **dnsmasq** - DHCP сервер (раздает IP клиентам) + DNS сервер

## 🔧 Полная настройка hostapd

### Базовая конфигурация

```bash
sudo nano /etc/hostapd/hostapd.conf
```

```conf
# Основные настройки
interface=wlan0
driver=nl80211

# SSID и режим
ssid=ShadowPi
hw_mode=g
channel=7

# Безопасность WPA2
auth_algs=1
wpa=2
wpa_key_mgmt=WPA-PSK
wpa_passphrase=YourSecurePassword123
rsn_pairwise=CCMP

# Отключить broadcast SSID (скрытая сеть, опционально)
# ignore_broadcast_ssid=1

# Производительность (802.11n)
ieee80211n=1
ht_capab=[HT40][SHORT-GI-20][SHORT-GI-40][DSSS_CCK-40]
wmm_enabled=1

# Ограничение клиентов (опционально)
max_num_sta=10

# Логи
logger_syslog=-1
logger_syslog_level=2
logger_stdout=-1
logger_stdout_level=2

# Страна (для правильных каналов и мощности)
country_code=RU
```

### Расшифровка параметров:

| Параметр | Значение | Описание |
|----------|----------|----------|
| `interface` | wlan0 | WiFi интерфейс для AP |
| `driver` | nl80211 | Драйвер (стандартный для Pi) |
| `ssid` | Название сети | Имя вашей WiFi сети |
| `hw_mode` | g | 2.4GHz (a=5GHz, g=2.4GHz, ac=5GHz 802.11ac) |
| `channel` | 1-14 | Канал WiFi (1,6,11 меньше пересечений) |
| `wpa` | 2 | WPA2 (самый безопасный) |
| `wpa_passphrase` | Пароль | Минимум 8 символов |
| `max_num_sta` | Число | Максимум подключенных клиентов |

### Продвинутые настройки

```bash
# Для 5GHz WiFi (если поддерживается)
hw_mode=a
channel=36
ieee80211ac=1
ht_capab=[HT40+][SHORT-GI-20][SHORT-GI-40]
vht_capab=[MAX-MPDU-11454][SHORT-GI-80][TX-STBC-2BY1][RX-STBC-1]
vht_oper_chwidth=1
vht_oper_centr_freq_seg0_idx=42

# MAC фильтрация (только определенные устройства)
macaddr_acl=1
accept_mac_file=/etc/hostapd/accept.mac
# В файле /etc/hostapd/accept.mac:
# aa:bb:cc:dd:ee:ff  # MAC адрес доверенного устройства
# 11:22:33:44:55:66  # Еще один

# WPA3 (если поддерживается)
wpa=2
wpa_key_mgmt=SAE WPA-PSK
rsn_pairwise=CCMP
ieee80211w=2
sae_password=YourStrongPassword
```

### Применение конфигурации

```bash
# Укажите путь к конфигу
sudo nano /etc/default/hostapd

# Добавьте/измените:
DAEMON_CONF="/etc/hostapd/hostapd.conf"

# Размаскируйте сервис (если нужно)
sudo systemctl unmask hostapd

# Включите автозапуск
sudo systemctl enable hostapd

# Запустите
sudo systemctl start hostapd

# Проверка
sudo systemctl status hostapd
```

### Тест вручную (для отладки)

```bash
# Остановите сервис
sudo systemctl stop hostapd

# Запустите в debug режиме
sudo hostapd -dd /etc/hostapd/hostapd.conf

# Вы увидите все логи в реальном времени
# Ctrl+C для остановки
```

## 🌐 Настройка dnsmasq

### Полная конфигурация

```bash
sudo nano /etc/dnsmasq.conf
```

```conf
# Интерфейс для прослушивания
interface=wlan0

# Не слушать на других интерфейсах
bind-interfaces
except-interface=eth0

# DHCP настройки
dhcp-range=10.0.0.10,10.0.0.250,255.255.255.0,24h
dhcp-option=3,10.0.0.1     # Gateway (сам роутер)
dhcp-option=6,10.0.0.1     # DNS сервер (сам роутер)

# Domain
domain=anonrouter.local
local=/anonrouter.local/

# Адрес роутера
address=/anonrouter.local/10.0.0.1

# DNS upstream серверы (через VPN)
server=1.1.1.1
server=8.8.8.8
# Или используйте VPN DNS:
# server=10.255.255.1

# Кеш DNS
cache-size=1000

# DHCP авторитетный сервер
dhcp-authoritative

# No query logging: a privacy router must not keep a record of what clients resolve.
# Do NOT add log-queries / log-dhcp. To debug, run it once in the foreground instead:
#   sudo systemctl stop dnsmasq && sudo dnsmasq -d -q   (Ctrl+C, then start the service again)
quiet-dhcp

# Listen only on the hotspot's own address. Without this dnsmasq binds port 53 on ALL
# addresses and fails to start ("Address already in use") when systemd-resolved is running.
bind-dynamic

# Игнорировать resolv.conf (используем наши DNS)
no-resolv

# DHCP статические лизы (опционально)
# dhcp-host=aa:bb:cc:dd:ee:ff,10.0.0.100,laptop
# dhcp-host=11:22:33:44:55:66,10.0.0.101,phone

# Блокировка рекламы (опционально)
# address=/ads.example.com/0.0.0.0
# address=/tracker.example.com/0.0.0.0
```

### Применение

```bash
# Включите автозапуск
sudo systemctl enable dnsmasq

# Запустите
sudo systemctl start dnsmasq

# Проверка
sudo systemctl status dnsmasq
```

### Тестирование dnsmasq

```bash
# Проверьте что слушает на правильном интерфейсе
sudo netstat -nlp | grep dnsmasq

# Должно быть:
# udp 0.0.0.0:53 (DNS)
# udp 0.0.0.0:67 (DHCP)

# Проверьте DNS резолвинг
dig @10.0.0.1 google.com

# Проверьте DHCP лизы
cat /var/lib/misc/dnsmasq.leases
```

## 🔌 Настройка сетевых интерфейсов

### Статический IP для wlan0

```bash
sudo nano /etc/dhcpcd.conf
```

Добавьте в конец:

```conf
# Static IP for wlan0 (WiFi Hotspot)
interface wlan0
static ip_address=10.0.0.1/24
nohook wpa_supplicant
```

### Альтернатива: через systemd-networkd

```bash
sudo nano /etc/systemd/network/10-wlan0.network
```

```ini
[Match]
Name=wlan0

[Network]
Address=10.0.0.1/24
DHCPServer=yes

[DHCPServer]
PoolOffset=10
PoolSize=240
EmitDNS=yes
DNS=10.0.0.1
```

```bash
# Включите systemd-networkd
sudo systemctl enable systemd-networkd
sudo systemctl start systemd-networkd
```

## 🚀 Запуск WiFi Hotspot

### Полный скрипт запуска

```bash
sudo nano /opt/shadowpi/scripts/start-wifi.sh
```

```bash
#!/bin/bash
# Start WiFi Hotspot

set -e

echo "📶 Запуск WiFi Hotspot..."

# 1. Остановить wpa_supplicant (если использует wlan0)
sudo killall wpa_supplicant 2>/dev/null || true

# 2. Разблокировать WiFi
sudo rfkill unblock wifi

# 3. Поднять интерфейс
sudo ip link set wlan0 down
sudo ip link set wlan0 up

# 4. Установить статический IP
sudo ip addr flush dev wlan0
sudo ip addr add 10.0.0.1/24 dev wlan0

# 5. Запустить hostapd
sudo systemctl start hostapd

# Подождать 2 секунды
sleep 2

# 6. Запустить dnsmasq
sudo systemctl start dnsmasq

echo "✅ WiFi Hotspot запущен!"
echo "   SSID: $(grep '^ssid=' /etc/hostapd/hostapd.conf | cut -d'=' -f2)"
echo "   IP: 10.0.0.1"
echo "   DHCP Range: 10.0.0.10 - 10.0.0.250"

# Показать подключенных клиентов
echo ""
echo "Подключенные клиенты:"
iw dev wlan0 station dump | grep Station | wc -l
```

```bash
sudo chmod +x /opt/shadowpi/scripts/start-wifi.sh

# Запуск
sudo /opt/shadowpi/scripts/start-wifi.sh
```

## 📊 Мониторинг WiFi

### Просмотр подключенных клиентов

```bash
# Список MAC адресов клиентов
sudo iw dev wlan0 station dump

# Просто количество
sudo iw dev wlan0 station dump | grep Station | wc -l

# С именами (из DHCP лизов)
cat /var/lib/misc/dnsmasq.leases

# Детальный статус
sudo iw dev wlan0 info
```

### Скрипт мониторинга

```bash
#!/bin/bash
# WiFi Monitor

while true; do
    clear
    echo "═══ WiFi Hotspot Status ═══"
    echo ""
    
    # SSID
    SSID=$(grep '^ssid=' /etc/hostapd/hostapd.conf | cut -d'=' -f2)
    echo "SSID: $SSID"
    
    # Канал
    CHANNEL=$(sudo iw dev wlan0 info | grep channel | awk '{print $2}')
    echo "Channel: $CHANNEL"
    
    # Подключенные клиенты
    CLIENTS=$(sudo iw dev wlan0 station dump | grep Station | wc -l)
    echo "Clients: $CLIENTS"
    
    echo ""
    echo "Connected Devices:"
    echo "────────────────────────────────────"
    
    # DHCP leases
    if [ -f /var/lib/misc/dnsmasq.leases ]; then
        cat /var/lib/misc/dnsmasq.leases | while read line; do
            MAC=$(echo $line | awk '{print $2}')
            IP=$(echo $line | awk '{print $3}')
            NAME=$(echo $line | awk '{print $4}')
            echo "  $IP  $MAC  $NAME"
        done
    fi
    
    sleep 5
done
```

## 🔒 Безопасность WiFi

### Улучшение безопасности

```bash
# 1. Скрытая сеть (не рекомендуется, легко обнаружить)
# В hostapd.conf:
ignore_broadcast_ssid=1

# 2. MAC фильтрация (белый список)
macaddr_acl=1
accept_mac_file=/etc/hostapd/accept.mac

# 3. WPA3 (если железо поддерживает)
wpa=2
wpa_key_mgmt=SAE
ieee80211w=2

# 4. Ограничение клиентов
max_num_sta=5

# 5. Изоляция клиентов (не видят друг друга)
ap_isolate=1
```

### Отключение WPS (уязвимость)

```bash
# В hostapd.conf убедитесь что НЕТ:
# wps_state=2

# Или явно отключите:
wps_state=0
```

## ⚡ Оптимизация производительности

### Для максимальной скорости

```bash
# В hostapd.conf:

# 802.11n с 40MHz каналами
ieee80211n=1
ht_capab=[HT40+][SHORT-GI-20][SHORT-GI-40][DSSS_CCK-40]

# 802.11ac для 5GHz (если поддерживается)
ieee80211ac=1
vht_oper_chwidth=1

# WMM (Quality of Service)
wmm_enabled=1

# Увеличить TX power (осторожно!)
# Проверьте легальность в вашей стране
#txpower=30  # в dBm
```

### Выбор канала

```bash
# Сканирование соседних сетей
sudo iwlist wlan0 scan | grep -E 'ESSID|Channel'

# Выберите наименее загруженный канал
# Рекомендуется: 1, 6, или 11 (не пересекаются)

# В hostapd.conf:
channel=1  # или 6, или 11
```

## 🐛 Troubleshooting WiFi

### WiFi не стартует

```bash
# Проверьте что wlan0 существует
iwconfig

# Проверьте драйверы
lsmod | grep 80211

# Проверьте rfkill
sudo rfkill list

# Разблокируйте если заблокирован
sudo rfkill unblock wifi

# Проверьте конфликты с NetworkManager
sudo systemctl stop NetworkManager
```

### Клиенты не могут подключиться

```bash
# Проверьте пароль (минимум 8 символов)
grep wpa_passphrase /etc/hostapd/hostapd.conf

# Проверьте канал (попробуйте 1, 6, или 11)
# Проверьте логи
sudo journalctl -u hostapd -f

# Попробуйте другой hw_mode
# g = 2.4GHz, a = 5GHz
```

### Нет DHCP (клиенты не получают IP)

```bash
# Проверьте dnsmasq работает
sudo systemctl status dnsmasq

# Проверьте что слушает на wlan0
sudo netstat -nlp | grep dnsmasq

# Проверьте конфигурацию
sudo dnsmasq --test

# Service log (startup and errors only; DNS queries are not logged on purpose)
sudo journalctl -u dnsmasq -n 50 --no-pager
```

## ✅ Готово!

WiFi Hotspot настроен! Переходите к **07_4G_MODEM.md**
