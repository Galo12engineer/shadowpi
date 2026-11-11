#!/bin/bash

###############################################################################
# SHADOWPI MASTER INSTALLATION SCRIPT
# Автоматическая установка ShadowPi - Secure Privacy Router
###############################################################################

set -e  # Выход при ошибке

# Корень репозитория (скрипт лежит в scripts/)
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Функции вывода
print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_header() {
    echo -e "\n${BLUE}═══════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════${NC}\n"
}

###############################################################################
# Проверка прав и системы
###############################################################################

print_header "Проверка системы"

if [ "$EUID" -ne 0 ]; then 
    print_error "Запустите скрипт с sudo!"
    exit 1
fi

print_success "Запущено с правами root"

# Проверка архитектуры
ARCH=$(uname -m)
if [[ "$ARCH" != "aarch64" && "$ARCH" != "armv7l" ]]; then
    print_warning "Не Raspberry Pi архитектура: $ARCH"
    read -p "Продолжить? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

print_success "Архитектура: $ARCH"

###############################################################################
# Интерактивная настройка
###############################################################################

print_header "Настройка параметров"

# WiFi Hotspot настройки
read -p "SSID для WiFi hotspot [ShadowPi]: " WIFI_SSID
WIFI_SSID=${WIFI_SSID:-ShadowPi}

read -p "Пароль WiFi (минимум 8 символов): " WIFI_PASSWORD
while [ ${#WIFI_PASSWORD} -lt 8 ]; do
    print_error "Пароль WiFi должен быть минимум 8 символов!"
    read -p "Пароль WiFi: " WIFI_PASSWORD
done

# Веб-панель
read -p "Пароль для веб-панели (admin): " WEB_PASSWORD
while [ ${#WEB_PASSWORD} -lt 6 ]; do
    print_error "Пароль должен быть минимум 6 символов!"
    read -p "Пароль для веб-панели: " WEB_PASSWORD
done

# WAN интерфейс
print_info "Выберите WAN интерфейс:"
echo "1) Ethernet (eth0) - по умолчанию"
echo "2) USB 4G/LTE модем (настроить позже)"
read -p "Выбор [1]: " WAN_CHOICE
WAN_CHOICE=${WAN_CHOICE:-1}

if [ "$WAN_CHOICE" == "1" ]; then
    WAN_INTERFACE="eth0"
else
    WAN_INTERFACE="wwan0"
    INSTALL_MODEM=true
fi

# Tor опция
read -p "Установить Tor для дополнительной анонимности? (y/n) [y]: " INSTALL_TOR
INSTALL_TOR=${INSTALL_TOR:-y}

print_info "Конфигурация:"
echo "  SSID: $WIFI_SSID"
echo "  WiFi Password: $WIFI_PASSWORD"
echo "  WAN: $WAN_INTERFACE"
echo "  Tor: $INSTALL_TOR"
echo ""
read -p "Начать установку? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 0
fi

###############################################################################
# Обновление системы
###############################################################################

print_header "Обновление системы"

apt update
apt upgrade -y

print_success "Система обновлена"

###############################################################################
# Установка базовых пакетов
###############################################################################

print_header "Установка базовых пакетов"

apt install -y \
    vim \
    curl \
    wget \
    git \
    htop \
    iftop \
    iotop \
    net-tools \
    iptables \
    nftables \
    tcpdump \
    dnsutils \
    jq \
    ca-certificates \
    gnupg \
    lsb-release

print_success "Базовые пакеты установлены"

###############################################################################
# Отключение IPv6
###############################################################################

print_header "Отключение IPv6 (защита от утечек)"

cat >> /etc/sysctl.conf << EOF

# Disable IPv6 (leak protection)
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF

sysctl -p

print_success "IPv6 отключен"

###############################################################################
# IP Forwarding
###############################################################################

print_header "Включение IP forwarding"

cat >> /etc/sysctl.conf << EOF

# Enable IP forwarding
net.ipv4.ip_forward = 1
EOF

sysctl -p

print_success "IP forwarding включен"

###############################################################################
# Установка OpenVPN
###############################################################################

print_header "Установка OpenVPN"

apt install -y openvpn openvpn-systemd-resolved

mkdir -p /etc/openvpn/client
mkdir -p /etc/openvpn/auth
mkdir -p /etc/openvpn/scripts
mkdir -p /var/log/openvpn

print_success "OpenVPN установлен"

###############################################################################
# Установка XRay + v2rayA
###############################################################################

print_header "Установка XRay и v2rayA"

# XRay core
print_info "Установка XRay core..."
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

# v2rayA (Web UI)
print_info "Установка v2rayA..."
wget -qO - https://apt.v2raya.org/key/public-key.asc | tee /etc/apt/trusted.gpg.d/v2raya.asc

echo "deb https://apt.v2raya.org/ v2raya main" | tee /etc/apt/sources.list.d/v2raya.list

apt update
apt install -y v2raya

systemctl enable v2raya
systemctl start v2raya

print_success "XRay и v2rayA установлены"

###############################################################################
# Установка Tor (опционально)
###############################################################################

if [[ "$INSTALL_TOR" =~ ^[Yy]$ ]]; then
    print_header "Установка Tor"
    
    apt install -y tor tor-geoipdb
    
    systemctl stop tor
    systemctl disable tor
    
    print_success "Tor установлен (отключен по умолчанию)"
fi

###############################################################################
# Установка WiFi Hotspot
###############################################################################

print_header "Установка WiFi Hotspot (hostapd + dnsmasq)"

apt install -y hostapd dnsmasq

systemctl stop hostapd
systemctl stop dnsmasq

# Резервное копирование конфигов
cp /etc/dnsmasq.conf /etc/dnsmasq.conf.bak 2>/dev/null || true
cp /etc/dhcpcd.conf /etc/dhcpcd.conf.bak 2>/dev/null || true

# Настройка статического IP для wlan0
cat >> /etc/dhcpcd.conf << EOF

# Static IP for wlan0 (WiFi Hotspot)
interface wlan0
    static ip_address=10.0.0.1/24
    nohook wpa_supplicant
EOF

# dnsmasq конфигурация
cat > /etc/dnsmasq.conf << EOF
# WiFi Hotspot DHCP + DNS
interface=wlan0
dhcp-range=10.0.0.10,10.0.0.250,255.255.255.0,24h
domain=anonrouter.local
address=/anonrouter.local/10.0.0.1

# DNS серверы
server=1.1.1.1
server=8.8.8.8

# No query logging: a privacy router must not keep a record of what clients resolve.
# (Do not add log-queries / log-dhcp here; for debugging run dnsmasq by hand with -q.)
quiet-dhcp
EOF

# hostapd конфигурация
cat > /etc/hostapd/hostapd.conf << EOF
# WiFi Access Point Configuration
interface=wlan0
driver=nl80211
ssid=$WIFI_SSID
hw_mode=g
channel=7
wmm_enabled=0
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=$WIFI_PASSWORD
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP

# Performance
ieee80211n=1
ht_capab=[HT40][SHORT-GI-20][DSSS_CCK-40]
EOF

# Указать путь к конфигу
echo 'DAEMON_CONF="/etc/hostapd/hostapd.conf"' >> /etc/default/hostapd

# Размаскировать hostapd если нужно
systemctl unmask hostapd

print_success "WiFi Hotspot настроен (SSID: $WIFI_SSID)"

###############################################################################
# Установка ModemManager (если выбран 4G)
###############################################################################

if [ "$INSTALL_MODEM" = true ]; then
    print_header "Установка поддержки 4G/LTE модема"
    
    apt install -y \
        modemmanager \
        usb-modeswitch \
        usb-modeswitch-data \
        mobile-broadband-provider-info \
        libqmi-utils \
        libmbim-utils
    
    systemctl enable ModemManager
    systemctl start ModemManager
    
    print_success "ModemManager установлен"
fi

###############################################################################
# Установка Nginx + PHP (Веб-панель)
###############################################################################

print_header "Установка Nginx и PHP"

apt install -y nginx php-fpm php-cli php-common

# Генерация хеша пароля
WEB_PASSWORD_HASH=$(openssl passwd -apr1 "$WEB_PASSWORD")

# Создание htpasswd файла
mkdir -p /etc/nginx/auth
echo "admin:$WEB_PASSWORD_HASH" > /etc/nginx/auth/htpasswd

# Nginx конфигурация для веб-панели
cat > /etc/nginx/sites-available/shadowpi << 'EOF'
server {
    listen 8080;
    server_name _;

    root /var/www/shadowpi;
    index index.php index.html;
    
    # Basic auth
    auth_basic "ShadowPi Admin";
    auth_basic_user_file /etc/nginx/auth/htpasswd;
    
    location / {
        try_files $uri $uri/ =404;
    }
    
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php-fpm.sock;
    }
    
    location ~ /\.ht {
        deny all;
    }
}
EOF

ln -sf /etc/nginx/sites-available/shadowpi /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

systemctl enable nginx
systemctl restart nginx

print_success "Nginx установлен (порт 8080)"

###############################################################################
# Создание структуры проекта
###############################################################################

print_header "Создание структуры каталогов"

mkdir -p /opt/shadowpi/{scripts,configs,logs,status,backups}
mkdir -p /var/www/shadowpi
mkdir -p /var/log/shadowpi

chown -R $SUDO_USER:$SUDO_USER /opt/shadowpi
chown -R www-data:www-data /var/log/shadowpi

# Panel state that only PHP may read or write (failed-login counters for the lockout)
install -d -o www-data -g www-data -m 0700 /var/lib/shadowpi

print_success "Структура каталогов создана"

###############################################################################
# Скрипты, веб-панель и права
###############################################################################

print_header "Установка скриптов и веб-панели"

# Скрипты запускаются из веб-панели через sudo, поэтому принадлежат root
# и недоступны для записи никому, кроме root.
install -o root -g root -m 0755 "$PROJECT_DIR"/scripts/*.sh /opt/shadowpi/scripts/
chown root:root /opt/shadowpi/scripts

cp -r "$PROJECT_DIR"/web-ui/. /var/www/shadowpi/

# Хеш пароля панели (bcrypt) записывается в config.php
php -r '
$file = $argv[1];
$hash = password_hash($argv[2], PASSWORD_DEFAULT);
$code = file_get_contents($file);
$code = preg_replace_callback(
    "/define\(\x27AUTH_PASSWORD_HASH\x27, \x27[^\x27]*\x27\)/",
    function () use ($hash) { return "define(\x27AUTH_PASSWORD_HASH\x27, " . var_export($hash, true) . ")"; },
    $code
);
file_put_contents($file, $code);
' /var/www/shadowpi/config.php "$WEB_PASSWORD"

chown -R root:www-data /var/www/shadowpi
chmod -R u=rwX,g=rX,o= /var/www/shadowpi

# www-data может запускать через sudo только эти команды
cat > /etc/sudoers.d/shadowpi << 'EOF'
Cmnd_Alias SHADOWPI_SVC = /usr/bin/systemctl start openvpn-windscribe, /usr/bin/systemctl stop openvpn-windscribe, /usr/bin/systemctl restart openvpn-windscribe, \
                          /usr/bin/systemctl start v2raya, /usr/bin/systemctl stop v2raya, /usr/bin/systemctl restart v2raya, \
                          /usr/bin/systemctl start tor, /usr/bin/systemctl stop tor, /usr/bin/systemctl restart tor, \
                          /usr/bin/systemctl start hostapd, /usr/bin/systemctl stop hostapd, /usr/bin/systemctl restart hostapd, \
                          /usr/bin/systemctl start dnsmasq, /usr/bin/systemctl stop dnsmasq, /usr/bin/systemctl restart dnsmasq
Cmnd_Alias SHADOWPI_SCRIPTS = /opt/shadowpi/scripts/start-all.sh, /opt/shadowpi/scripts/stop-all.sh, \
                              /opt/shadowpi/scripts/restart-all.sh, /opt/shadowpi/scripts/test-all.sh, \
                              /opt/shadowpi/scripts/wan-switch.sh *, /opt/shadowpi/scripts/setup-modem.sh *
www-data ALL=(root) NOPASSWD: SHADOWPI_SVC, SHADOWPI_SCRIPTS
EOF
chmod 0440 /etc/sudoers.d/shadowpi
visudo -cf /etc/sudoers.d/shadowpi

print_success "Скрипты и веб-панель установлены"

###############################################################################
# Финальные настройки
###############################################################################

print_header "Финальные настройки"

# Разблокировка WiFi
rfkill unblock wifi

# Создание файла статуса
echo "installed" > /opt/shadowpi/status/install-status.txt
echo "$(date)" > /opt/shadowpi/status/install-date.txt

print_success "Установка завершена!"

###############################################################################
# Информация для пользователя
###############################################################################

print_header "УСТАНОВКА ЗАВЕРШЕНА!"

echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}   🔒 ShadowPi установлен!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${BLUE}📶 WiFi Hotspot:${NC}"
echo "   SSID: $WIFI_SSID"
echo "   Пароль: $WIFI_PASSWORD"
echo ""
echo -e "${BLUE}🌐 Веб-панели:${NC}"
echo "   Панель управления: http://anonrouter.local:8080"
echo "     Логин: admin"
echo "     Пароль: $WEB_PASSWORD"
echo ""
echo "   v2rayA (прокси): http://anonrouter.local:2017"
echo ""
echo -e "${BLUE}📋 Следующие шаги:${NC}"
echo "   1. Скопируйте Windscribe .ovpn конфиг:"
echo "      scp windscribe.ovpn admin@anonrouter.local:/tmp/"
echo ""
echo "   2. Настройте OpenVPN:"
echo "      Смотрите docs/03_OPENVPN_SETUP.md"
echo ""
echo "   3. Добавьте прокси в v2rayA:"
echo "      Откройте http://anonrouter.local:2017"
echo ""
echo "   4. Запустите систему:"
echo "      sudo systemctl start openvpn-windscribe"
echo "      sudo systemctl start v2raya"
echo "      sudo systemctl start hostapd"
echo "      sudo systemctl start dnsmasq"
echo ""
echo -e "${YELLOW}⚠️  ВАЖНО: Перезагрузите Pi для применения всех настроек:${NC}"
echo "   sudo reboot"
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
