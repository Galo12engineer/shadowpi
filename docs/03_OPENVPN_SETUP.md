# 03. Настройка OpenVPN (Windscribe)

## Получение конфигурации Windscribe

### Метод 1: Через веб-сайт

1. Войдите на https://windscribe.com
2. Перейдите в **My Account** → **Config Generator**
3. Выберите:
   - Protocol: **OpenVPN**
   - Config Type: **Manual**
   - Location: Выберите сервер (например, Netherlands, Switzerland для анонимности)
   - Port: **TCP 443** или **UDP 443** (UDP быстрее, но можно заблокировать)
4. Скачайте `.ovpn` файл

### Метод 2: Универсальный конфиг

Windscribe предоставляет также универсальные конфиги со всеми серверами.

## Шаг 1: Загрузка конфига на Pi

```bash
# НА ВАШЕМ КОМПЬЮТЕРЕ (Mac):
# Скопируйте .ovpn файл на Pi
scp ~/Downloads/Windscribe-Netherlands.ovpn admin@anonrouter.local:/tmp/

# ИЛИ создайте на Pi напрямую используя nano
```

## Шаг 2: Установка конфига

```bash
# SSH на Pi
ssh admin@anonrouter.local

# Переместите конфиг
sudo mv /tmp/Windscribe-Netherlands.ovpn /etc/openvpn/client/windscribe.conf

# Создайте файл с учетными данными
sudo nano /etc/openvpn/auth/windscribe-auth.txt

# Добавьте (первая строка - username, вторая - password):
your_windscribe_username
your_windscribe_password

# Сохраните: Ctrl+O, Enter, Ctrl+X

# Установите права доступа (важно для безопасности!)
sudo chmod 600 /etc/openvpn/auth/windscribe-auth.txt
sudo chown root:root /etc/openvpn/auth/windscribe-auth.txt
```

## Шаг 3: Модификация конфига для автоматической авторизации

```bash
# Откройте конфиг
sudo nano /etc/openvpn/client/windscribe.conf

# Найдите строку:
# auth-user-pass

# Замените на:
auth-user-pass /etc/openvpn/auth/windscribe-auth.txt

# Добавьте в конец файла для предотвращения DNS утечек:
script-security 2
up /etc/openvpn/scripts/up.sh
down /etc/openvpn/scripts/down.sh

# Также добавьте для логов:
log /var/log/openvpn/openvpn.log
log-append /var/log/openvpn/openvpn.log
verb 3

# Весь трафик (и роутера, и Wi-Fi клиентов) — через VPN.
# def1 добавляет маршруты 0.0.0.0/1 и 128.0.0.0/1 через tun0: они точнее,
# чем default через eth0, поэтому выигрывают, пока VPN поднят.
# Если VPN упадёт, маршруты исчезнут, и трафик клиентов упрётся в killswitch
# (FORWARD wlan0 → eth0 DROP, docs/08_FIREWALL.md). НЕ добавляйте
# pull-filter ignore "redirect-gateway": тогда default остаётся на eth0,
# killswitch его режет, и у клиентов нет интернета даже при живом VPN.
redirect-gateway def1

# Сохраните: Ctrl+O, Enter, Ctrl+X
```

## Шаг 4: Создание скриптов up/down

Эти скрипты будут выполняться при подключении/отключении VPN.

```bash
# Создайте директорию
sudo mkdir -p /etc/openvpn/scripts
sudo mkdir -p /var/log/openvpn

# Создайте UP скрипт
sudo nano /etc/openvpn/scripts/up.sh
```

Вставьте:

```bash
#!/bin/bash
# OpenVPN UP script

echo "[$(date)] OpenVPN UP: Interface $dev, IP $ifconfig_local" >> /var/log/openvpn/connection.log

# Настройка маршрутизации через VPN
# (NAT будет настроен в firewall секции)

# DNS через VPN (против утечек)
echo "nameserver 10.255.255.1" > /etc/resolv.conf
echo "nameserver 8.8.8.8" >> /etc/resolv.conf

# Уведомить веб-панель о статусе
echo "connected" > /opt/shadowpi/status/vpn-status.txt
echo "$ifconfig_local" > /opt/shadowpi/status/vpn-ip.txt

exit 0
```

```bash
# Создайте DOWN скрипт
sudo nano /etc/openvpn/scripts/down.sh
```

Вставьте:

```bash
#!/bin/bash
# OpenVPN DOWN script

echo "[$(date)] OpenVPN DOWN: Interface $dev" >> /var/log/openvpn/connection.log

# Восстановить DNS
echo "nameserver 1.1.1.1" > /etc/resolv.conf
echo "nameserver 8.8.8.8" >> /etc/resolv.conf

# Уведомить веб-панель
echo "disconnected" > /opt/shadowpi/status/vpn-status.txt

exit 0
```

```bash
# Сделайте скрипты исполняемыми
sudo chmod +x /etc/openvpn/scripts/up.sh
sudo chmod +x /etc/openvpn/scripts/down.sh

# Создайте папку для статусов
sudo mkdir -p /opt/shadowpi/status
sudo chown admin:admin /opt/shadowpi/status
```

## Шаг 5: Тестирование OpenVPN

```bash
# Тест подключения вручную (без автозапуска)
sudo openvpn --config /etc/openvpn/client/windscribe.conf

# Вы должны увидеть:
# "Initialization Sequence Completed"

# Проверьте IP (в другом терминале SSH):
curl ipinfo.io

# Должен показать IP VPN сервера!

# Остановите тест: Ctrl+C
```

## Шаг 6: Настройка systemd сервиса

```bash
# Создайте systemd unit
sudo nano /etc/systemd/system/openvpn-windscribe.service
```

Вставьте:

```ini
[Unit]
Description=OpenVPN connection to Windscribe
After=network-online.target
Wants=network-online.target
Before=v2raya.service

[Service]
Type=notify
PrivateTmp=true
WorkingDirectory=/etc/openvpn/client
ExecStart=/usr/sbin/openvpn --suppress-timestamps --nobind --config windscribe.conf
CapabilityBoundingSet=CAP_IPC_LOCK CAP_NET_ADMIN CAP_NET_RAW CAP_SETGID CAP_SETUID CAP_SYS_CHROOT CAP_DAC_OVERRIDE
LimitNPROC=10
DeviceAllow=/dev/null rw
DeviceAllow=/dev/net/tun rw
ProtectSystem=true
ProtectHome=true
KillMode=process
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

```bash
# Сохраните и включите сервис
sudo systemctl daemon-reload
sudo systemctl enable openvpn-windscribe
sudo systemctl start openvpn-windscribe

# Проверьте статус
sudo systemctl status openvpn-windscribe

# Проверьте логи
sudo journalctl -u openvpn-windscribe -f
# (Ctrl+C для выхода)

# Проверьте IP
curl ipinfo.io
```

## Шаг 7: Проверка tun интерфейса

```bash
# Проверьте что tun0 создан
ip addr show tun0

# Должно показать:
# tun0: <POINTOPOINT,MULTICAST,NOARP,UP,LOWER_UP>
# inet 10.x.x.x/xx ...

# Проверьте маршрут
ip route show

# Должен быть маршрут через tun0
```

## Шаг 8: DNS Leak Test

```bash
# Установите инструмент
sudo pip3 install dnsleaktest --break-system-packages

# Проверьте DNS утечки
dnsleaktest

# Должен показать DNS серверы Windscribe, НЕ вашего провайдера!
```

## 🔧 Управление OpenVPN

```bash
# Запуск
sudo systemctl start openvpn-windscribe

# Остановка
sudo systemctl stop openvpn-windscribe

# Перезапуск
sudo systemctl restart openvpn-windscribe

# Статус
sudo systemctl status openvpn-windscribe

# Логи реального времени
sudo journalctl -u openvpn-windscribe -f

# Логи OpenVPN
sudo tail -f /var/log/openvpn/openvpn.log
```

## 🐛 Troubleshooting

### Проблема: Auth Failed

```bash
# Проверьте учетные данные
sudo cat /etc/openvpn/auth/windscribe-auth.txt

# Убедитесь что нет лишних пробелов/переносов строк
# Должно быть РОВНО 2 строки: username и password
```

### Проблема: Connection Timeout

```bash
# Попробуйте другой порт в конфиге
# В windscribe.conf найдите строку:
# remote xxx.windscribe.com 443

# Попробуйте другие порты: 443, 1194, 80, 123, 53

# Или попробуйте TCP вместо UDP:
proto tcp  # вместо proto udp
```

### Проблема: Медленная скорость

```bash
# 1. Используйте UDP вместо TCP
# 2. Попробуйте ближайший сервер
# 3. Включите comp-lzo в конфиге:
comp-lzo yes

# 4. Или лучше - переходите на WireGuard (см. альтернативы)
```

## 🚀 Альтернатива: WireGuard (быстрее!)

Если скорость важна, используйте WireGuard вместо OpenVPN:

```bash
# Установка
sudo apt install -y wireguard

# Windscribe поддерживает WireGuard!
# Получите конфиг на https://windscribe.com → Config Generator → WireGuard
```

## ✅ Готово!

OpenVPN настроен и работает! Переходите к **04_V2RAY_SETUP.md**

## 📝 Что сделано:

- ✅ OpenVPN установлен и подключен к Windscribe
- ✅ Автоматическая авторизация настроена
- ✅ systemd сервис создан (автозапуск при загрузке)
- ✅ Скрипты up/down для управления
- ✅ DNS leak protection
- ✅ Логи настроены
