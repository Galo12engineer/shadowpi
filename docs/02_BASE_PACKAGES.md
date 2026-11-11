# 02. Установка базовых пакетов

## Все необходимые компоненты

```bash
# SSH подключение к Pi
ssh admin@anonrouter.local
```

## Шаг 1: Настройка Swap (важно для Pi 3!)

> ⚠️ **Для Pi 3B/3B+ с 1GB RAM — обязательно!**
> Для Pi 4 с 4GB+ — можно пропустить или уменьшить до 1GB

```bash
# Проверка текущего swap
free -h

# Отключить текущий swap (если есть)
sudo dphys-swapfile swapoff

# Настройка размера swap
sudo nano /etc/dphys-swapfile
# Изменить строку:
# CONF_SWAPSIZE=100
# На:
# CONF_SWAPSIZE=2048

# Или одной командой:
sudo sed -i 's/CONF_SWAPSIZE=.*/CONF_SWAPSIZE=2048/' /etc/dphys-swapfile

# Применить изменения
sudo dphys-swapfile setup
sudo dphys-swapfile swapon

# Проверка (должно показать 2GB swap)
free -h

# Оптимизация swappiness (меньше = реже использует swap)
echo 'vm.swappiness=10' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

echo "✅ Swap настроен: 2GB"
```

**Рекомендации по размеру swap:**

| RAM устройства | Рекомендуемый Swap |
|----------------|-------------------|
| 1 GB (Pi 3)    | 2048 MB (2 GB)    |
| 2 GB (Pi 4)    | 1024 MB (1 GB)    |
| 4 GB (Pi 4)    | 512-1024 MB       |
| 8 GB (Pi 4/5)  | 512 MB или без    |

---

## Шаг 2: OpenVPN

```bash
# Установка OpenVPN
sudo apt install -y openvpn openvpn-systemd-resolved

# Создание директории для конфигов
sudo mkdir -p /etc/openvpn/client
sudo mkdir -p /etc/openvpn/auth

# Проверка установки
openvpn --version
```

## Шаг 3: V2Ray / XRay с v2rayA (Web UI)

v2rayA - это веб-интерфейс для V2Ray/XRay, как v2rayN в Windows.

```bash
# Установка XRay core
sudo bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

# Проверка XRay
xray version

# v2rayA (Web UI) - OPTIONAL. The VPN, the kill switch and the panel work without it.
# Do not use the apt.v2raya.org repository: it serves a certificate chain Debian does not
# trust, and switching TLS verification off ([trusted=yes], --allow-insecure) is not an option.
# Install the pinned release from GitHub and check its SHA-256 first
# (arm64 shown; the installer script has the values for armv7 and x64 too):
V=2.5.10
curl -fsSL -o /tmp/v2raya.deb "https://github.com/v2rayA/v2rayA/releases/download/v$V/installer_debian_arm64_$V.deb"
echo "c4ad561ba36df480222552e3595103ac4ae54d29141c6b03d53edab96ea15f67  /tmp/v2raya.deb" | sha256sum -c -
# Continue only if the line above printed "OK"
sudo apt install -y /tmp/v2raya.deb

# Включение и запуск v2rayA
sudo systemctl enable v2raya
sudo systemctl start v2raya

# Проверка статуса
sudo systemctl status v2raya

# v2rayA будет доступен на http://raspberrypi.local:2017
echo "✅ v2rayA установлен! Web UI: http://anonrouter.local:2017"
```

## Шаг 4: Tor (опционально)

```bash
# Установка Tor
sudo apt install -y tor tor-geoipdb

# Остановить пока (настроим позже)
sudo systemctl stop tor
sudo systemctl disable tor

# Проверка
tor --version
```

## Шаг 5: WiFi Hotspot (hostapd + dnsmasq)

```bash
# Установка hostapd (WiFi Access Point)
sudo apt install -y hostapd

# Установка dnsmasq (DHCP + DNS сервер)
sudo apt install -y dnsmasq

# Остановить сервисы (настроим позже)
sudo systemctl stop hostapd
sudo systemctl stop dnsmasq
sudo systemctl disable hostapd
sudo systemctl disable dnsmasq

# Проверка
hostapd -v
dnsmasq --version
```

## Шаг 6: Firewall (nftables)

```bash
# nftables (современная замена iptables)
sudo apt install -y nftables

# Включить сервис
sudo systemctl enable nftables

# Проверка
sudo nft --version
```

## Шаг 7: USB 4G/LTE Modem поддержка

```bash
# ModemManager для управления модемами
sudo apt install -y \
  modemmanager \
  usb-modeswitch \
  usb-modeswitch-data \
  mobile-broadband-provider-info

# Запуск ModemManager
sudo systemctl enable ModemManager
sudo systemctl start ModemManager

# Инструменты для работы с модемами
sudo apt install -y \
  libqmi-utils \
  libmbim-utils

# Проверка (если модем подключен)
mmcli -L
# Покажет список модемов
```

## Шаг 8: Веб-сервер (Nginx + PHP)

```bash
# Установка Nginx
sudo apt install -y nginx

# Установка PHP для веб-панели
sudo apt install -y php-fpm php-cli php-common

# Запуск Nginx
sudo systemctl enable nginx
sudo systemctl start nginx

# Проверка (должна открыться дефолтная страница Nginx)
curl http://localhost

echo "✅ Nginx установлен! Веб-сервер работает"
```

## Шаг 9: Дополнительные инструменты

```bash
# Инструменты для мониторинга и тестирования
sudo apt install -y \
  iftop \
  iotop \
  tcpdump \
  nmap \
  speedtest-cli \
  dnsutils \
  bind9-dnsutils \
  jq \
  python3-pip

# Установка better speedtest
sudo pip3 install speedtest-cli --break-system-packages

# Утилиты для работы с сетью
sudo apt install -y \
  iw \
  wireless-tools \
  wpasupplicant \
  rfkill

# Проверка WiFi не заблокирован
sudo rfkill unblock wifi
rfkill list
```

## Шаг 10: Создание структуры директорий

```bash
# Создание папки для нашего проекта
sudo mkdir -p /opt/shadowpi/{scripts,configs,logs,backups}

# Права доступа
sudo chown -R admin:admin /opt/shadowpi

# Создание папок для логов
sudo mkdir -p /var/log/shadowpi
sudo chown admin:admin /var/log/shadowpi

echo "✅ Структура директорий создана"
```

## Шаг 11: Проверка всех пакетов

```bash
# Создайте скрипт проверки
cat > /tmp/check-packages.sh << 'EOF'
#!/bin/bash

echo "🔍 Проверка установленных пакетов..."
echo

packages=(
  "openvpn:OpenVPN"
  "xray:XRay"
  "v2raya:v2rayA"
  "tor:Tor"
  "hostapd:Hostapd"
  "dnsmasq:Dnsmasq"
  "nft:nftables"
  "mmcli:ModemManager"
  "nginx:Nginx"
  "php-fpm8.2:PHP-FPM"
)

for pkg in "${packages[@]}"; do
  cmd="${pkg%%:*}"
  name="${pkg##*:}"
  
  if command -v $cmd &> /dev/null; then
    echo "✅ $name установлен"
  else
    echo "❌ $name НЕ установлен!"
  fi
done

echo
echo "🌐 Сервисы:"
services=("v2raya" "nginx" "ModemManager")

for svc in "${services[@]}"; do
  if systemctl is-active --quiet $svc; then
    echo "✅ $svc запущен"
  else
    echo "⚠️  $svc не запущен"
  fi
done
EOF

chmod +x /tmp/check-packages.sh
bash /tmp/check-packages.sh
```

## Шаг 12: Резервное копирование конфигов

```bash
# Создайте бэкап дефолтных конфигов
sudo cp /etc/sysctl.conf /opt/shadowpi/backups/sysctl.conf.bak
sudo cp /etc/dhcpcd.conf /opt/shadowpi/backups/dhcpcd.conf.bak 2>/dev/null || true

echo "✅ Бэкапы созданы в /opt/shadowpi/backups/"
```

## 📊 Проверка использования ресурсов

```bash
# Проверьте сколько памяти используется
free -h

# Проверьте диск
df -h

# Проверьте температуру
vcgencmd measure_temp

# Запустите htop для мониторинга
htop
# (нажмите q для выхода)
```

## ✅ Готово!

Все базовые пакеты установлены! Переходите к **03_OPENVPN_SETUP.md**

## 📝 Что установлено:

- ✅ OpenVPN - VPN клиент
- ✅ XRay - прокси core
- ✅ v2rayA - веб UI для управления прокси (http://anonrouter.local:2017)
- ✅ Tor - для дополнительной анонимности
- ✅ hostapd + dnsmasq - WiFi hotspot
- ✅ nftables - firewall
- ✅ ModemManager - поддержка 4G/LTE модемов
- ✅ Nginx + PHP - веб-сервер для панели управления
- ✅ Инструменты мониторинга и тестирования
