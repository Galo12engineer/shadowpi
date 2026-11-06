# 11. Troubleshooting (Решение проблем)

## Общие проблемы

### Проблема 1: VPN не подключается

**Симптомы:**
```bash
sudo systemctl status openvpn-windscribe
# Показывает: failed или inactive
```

**Решения:**

```bash
# 1. Проверьте логи
sudo journalctl -u openvpn-windscribe -n 50

# 2. Проверьте учетные данные
sudo cat /etc/openvpn/auth/windscribe-auth.txt
# Должно быть РОВНО 2 строки: username и password

# 3. Проверьте интернет соединение
ping -c 4 8.8.8.8

# 4. Попробуйте другой сервер Windscribe
sudo nano /etc/openvpn/client/windscribe.conf
# Измените строку: remote xxx.windscribe.com 443

# 5. Переключитесь с UDP на TCP
# В конфиге замените:
proto udp → proto tcp

# 6. Проверьте firewall
sudo iptables -L -n -v

# 7. Перезапустите
sudo systemctl restart openvpn-windscribe
```

**Типичные ошибки:**

| Ошибка | Причина | Решение |
|--------|---------|---------|
| `AUTH_FAILED` | Неверный логин/пароль | Проверьте auth file |
| `TLS handshake failed` | Проблема с сертификатами | Перекачайте .ovpn с сайта |
| `Connection timeout` | Порт заблокирован | Смените порт на 443 TCP |
| `Cannot resolve hostname` | DNS проблема | Используйте IP вместо hostname |

---

### Проблема 2: v2rayA не стартует

**Симптомы:**
```bash
sudo systemctl status v2raya
# Показывает: failed
```

**Решения:**

```bash
# 1. Проверьте XRay установлен
xray version

# 2. Проверьте порт 2017 свободен
sudo netstat -tlnp | grep 2017

# Если занят, убейте процесс:
sudo kill $(sudo lsof -t -i:2017)

# 3. Проверьте логи
sudo journalctl -u v2raya -n 100

# 4. Переустановите v2rayA
sudo systemctl stop v2raya
sudo apt remove v2raya -y
sudo apt install v2raya -y
sudo systemctl start v2raya

# 5. Проверьте конфигурацию
sudo v2raya --version
```

---

### Проблема 3: WiFi Hotspot не работает

**Симптомы:**
- WiFi сеть не видна
- Не удается подключиться
- Подключается но нет интернета

**Решения:**

```bash
# 1. Проверьте статус
sudo systemctl status hostapd
sudo systemctl status dnsmasq

# 2. Проверьте что wlan0 свободен
sudo rfkill unblock wifi
iwconfig wlan0

# 3. Проверьте конфигурацию hostapd
sudo nano /etc/hostapd/hostapd.conf

# Убедитесь:
interface=wlan0
driver=nl80211
channel=7  # Попробуйте другой канал (1, 6, 11)

# 4. Проверьте IP на wlan0
ip addr show wlan0
# Должно быть: inet 10.0.0.1/24

# Если нет, назначьте вручную:
sudo ip addr add 10.0.0.1/24 dev wlan0
sudo ip link set wlan0 up

# 5. Перезапустите сервисы
sudo systemctl restart hostapd
sudo systemctl restart dnsmasq

# 6. Проверьте логи
sudo journalctl -u hostapd -n 50
sudo tail -f /var/log/syslog | grep dnsmasq

# 7. Тест вручную
sudo hostapd -d /etc/hostapd/hostapd.conf
# Ctrl+C для остановки
```

**Частые проблемы с WiFi:**

- **Канал занят**: Смените channel в hostapd.conf (1, 6, или 11)
- **wlan0 используется NetworkManager**: Отключите NetworkManager для wlan0
- **Неверный пароль WiFi**: Минимум 8 символов в wpa_passphrase
- **Регион не установлен**: Добавьте `country_code=RU` в hostapd.conf

---

### Проблема 4: Нет интернета на клиентах WiFi

**Симптомы:**
- WiFi подключается
- Получает IP (10.0.0.x)
- Но нет доступа в интернет

**Решения:**

```bash
# 1. Проверьте IP forwarding
sysctl net.ipv4.ip_forward
# Должно быть = 1

# Если 0:
sudo sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf

# 2. Проверьте NAT правила
sudo iptables -t nat -L POSTROUTING -n -v

# Должно быть правило MASQUERADE для eth0 или tun0

# Добавьте если нет:
sudo iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
sudo iptables -t nat -A POSTROUTING -o tun0 -j MASQUERADE

# 3. Проверьте routing
ip route show

# 4. Проверьте DNS
# На клиенте:
nslookup google.com

# На Pi проверьте dnsmasq:
sudo systemctl status dnsmasq
dig @10.0.0.1 google.com

# 5. Проверьте firewall не блокирует
sudo iptables -L FORWARD -n -v

# 6. Тест пинга с клиента
ping 10.0.0.1   # Pi роутер (должно работать)
ping 8.8.8.8    # Google DNS (должно работать)
ping google.com # DNS резолв (должно работать)
```

---

### Проблема 5: Показывает реальный IP вместо VPN

**Симптомы:**
```bash
curl ipinfo.io
# Показывает ваш реальный IP провайдера
```

**Решения:**

```bash
# 1. Проверьте VPN подключен
ip addr show tun0
# Должен существовать

# 2. Проверьте маршрутизация через VPN
ip route | grep tun0

# 3. Проверьте default route
ip route show default

# 4. Проверьте V2Ray redirect правила
sudo iptables -t nat -L V2RAY -n -v

# 5. Заново примените redirect
sudo /opt/anon-router/scripts/setup-v2ray-redirect.sh

# 6. Проверьте цепочку
traceroute -T google.com

# 7. Перезапустите все
sudo /opt/anon-router/scripts/restart-all.sh
```

---

### Проблема 6: Медленная скорость

**Симптомы:**
- Скорость <5 Mbps
- Высокая задержка (>500ms)
- Постоянные обрывы

**Решения:**

```bash
# 1. Проверьте загрузку CPU
htop

# Если CPU >80%, у вас bottleneck

# 2. Смените OpenVPN на WireGuard
sudo apt install wireguard
# Скачайте WireGuard конфиг с Windscribe

# 3. Отключите Tor если включен
sudo systemctl stop tor

# 4. Используйте UDP вместо TCP для VPN
# В windscribe.conf:
proto udp

# 5. Смените V2Ray прокси на более быстрый
# Откройте v2rayA UI: http://anonrouter.local:2017
# Выберите сервер ближе к вам

# 6. Включите hardware crypto (если поддерживается)
# В openvpn конфиг:
ncp-ciphers AES-128-GCM

# 7. Уменьшите MTU
# В openvpn конфиг:
mssfix 1400
fragment 1400

# 8. Проверьте температуру Pi
vcgencmd measure_temp
# Если >75°C - нужно охлаждение!

# 9. Overclock Pi (осторожно!)
sudo raspi-config
# Performance Options → Overclock
```

**Оптимизация скорости:**

| Действие | Прирост скорости |
|----------|------------------|
| OpenVPN → WireGuard | +100-200% |
| Отключение Tor | +300-500% |
| UDP вместо TCP | +20-50% |
| Ближайший сервер | +50-100% |
| Охлаждение Pi | +10-20% |

---

### Проблема 7: DNS утечки

**Симптомы:**
```bash
# dnsleaktest.com показывает DNS вашего провайдера
```

**Решения:**

```bash
# 1. Проверьте текущие DNS
cat /etc/resolv.conf

# Должно быть:
nameserver 10.255.255.1  # VPN DNS
nameserver 8.8.8.8       # Резервный

# 2. Заблокируйте локальные DNS
sudo iptables -I OUTPUT -p udp --dport 53 ! -d 10.255.255.1 -j REJECT
sudo iptables -I OUTPUT -p tcp --dport 53 ! -d 10.255.255.1 -j REJECT

# 3. Принудительный DNS через VPN
# В /etc/openvpn/client/windscribe.conf добавьте:
dhcp-option DNS 10.255.255.1
block-outside-dns  # Только Windows

# 4. Используйте dnscrypt-proxy
sudo apt install dnscrypt-proxy
sudo systemctl enable dnscrypt-proxy

# 5. Настройте dnsmasq слушать только на wlan0
# В /etc/dnsmasq.conf:
interface=wlan0
no-dhcp-interface=eth0,tun0
```

---

### Проблема 8: Веб-панель не открывается

**Симптомы:**
- http://anonrouter.local:8080 не открывается
- 502 Bad Gateway
- Connection refused

**Решения:**

```bash
# 1. Проверьте Nginx
sudo systemctl status nginx

# 2. Проверьте порт 8080
sudo netstat -tlnp | grep 8080

# 3. Проверьте PHP-FPM
sudo systemctl status php*-fpm

# 4. Проверьте логи Nginx
sudo tail -f /var/log/nginx/error.log

# 5. Проверьте файлы веб-панели
ls -la /var/www/anonrouter/

# 6. Права доступа
sudo chown -R www-data:www-data /var/www/anonrouter
sudo chmod -R 755 /var/www/anonrouter

# 7. Тест PHP
echo "<?php phpinfo(); ?>" | sudo tee /var/www/anonrouter/test.php
curl http://localhost:8080/test.php

# 8. Перезапустите
sudo systemctl restart nginx
sudo systemctl restart php*-fpm

# 9. Используйте IP вместо hostname
# Узнайте IP Pi:
hostname -I
# Откройте: http://192.168.1.X:8080
```

---

### Проблема 9: 4G/LTE модем не определяется

**Симптомы:**
```bash
mmcli -L
# No modems found
```

**Решения:**

```bash
# 1. Проверьте модем подключен
lsusb
# Должен показать Huawei/ZTE устройство

# 2. Переключите режим
sudo usb_modeswitch -v 12d1 -p 1f01 -M '55534243...'

# 3. Проверьте ModemManager
sudo systemctl status ModemManager

# 4. Перезапустите
sudo systemctl restart ModemManager
sleep 5
mmcli -L

# 5. Принудительная настройка
mmcli -m 0 --simple-connect="apn=internet"

# 6. Проверьте wwan интерфейс
ip addr show wwan0

# 7. Логи
sudo journalctl -u ModemManager -f
```

---

### Проблема 10: Killswitch не работает

**Симптомы:**
- VPN отключился
- Но интернет все еще работает (показывает реальный IP)

**Решения:**

```bash
# 1. Создайте строгий firewall killswitch
sudo nano /opt/anon-router/scripts/killswitch.sh
```

Вставьте:

```bash
#!/bin/bash
# Killswitch firewall rules

# Flush existing rules
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X

# Default policies: DROP everything
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP

# Allow loopback
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# Allow local network (WiFi clients)
iptables -A INPUT -i wlan0 -j ACCEPT
iptables -A OUTPUT -o wlan0 -j ACCEPT

# Allow only through VPN
iptables -A OUTPUT -o tun0 -j ACCEPT
iptables -A INPUT -i tun0 -j ACCEPT

# Allow VPN connection itself
iptables -A OUTPUT -o eth0 -p udp --dport 443 -j ACCEPT
iptables -A INPUT -i eth0 -p udp --sport 443 -j ACCEPT

# NAT для клиентов через VPN
iptables -t nat -A POSTROUTING -o tun0 -j MASQUERADE

# FORWARD через VPN
iptables -A FORWARD -i wlan0 -o tun0 -j ACCEPT
iptables -A FORWARD -i tun0 -o wlan0 -m state --state RELATED,ESTABLISHED -j ACCEPT

echo "✅ Killswitch активирован"
```

```bash
sudo chmod +x /opt/anon-router/scripts/killswitch.sh
sudo /opt/anon-router/scripts/killswitch.sh

# 2. Автоматическая активация при загрузке
echo "/opt/anon-router/scripts/killswitch.sh" | sudo tee -a /etc/rc.local
```

---

## Общие советы по отладке

### Логи в реальном времени

```bash
# Одновременный мониторинг всех логов
sudo multitail \
  /var/log/openvpn/openvpn.log \
  -l "journalctl -u v2raya -f" \
  -l "journalctl -u hostapd -f"

# Или по отдельности в разных терминалах
# Terminal 1:
sudo tail -f /var/log/openvpn/openvpn.log

# Terminal 2:
sudo journalctl -u v2raya -f

# Terminal 3:
sudo journalctl -u hostapd -f
```

### Network debugging

```bash
# Мониторинг всего сетевого трафика
sudo tcpdump -i any -n -v

# Только DNS запросы
sudo tcpdump -i any port 53 -v

# Только VPN трафик
sudo tcpdump -i tun0 -n

# Сохранить в файл для анализа
sudo tcpdump -i any -w /tmp/capture.pcap

# Анализ в Wireshark (на компьютере)
scp admin@anonrouter.local:/tmp/capture.pcap .
wireshark capture.pcap
```

### Systemd debugging

```bash
# Детальный статус сервиса
sudo systemctl status openvpn-windscribe -l --no-pager

# Проверка зависимостей
systemctl list-dependencies openvpn-windscribe

# Проверка таймера автозапуска
systemctl list-timers

# Reload конфигов
sudo systemctl daemon-reload
```

---

## Крайние меры

### Полная переустановка

```bash
# 1. Сохраните важные конфиги
cp /etc/openvpn/client/windscribe.conf ~/backup/
cp /etc/openvpn/auth/windscribe-auth.txt ~/backup/

# 2. Остановите все
sudo /opt/anon-router/scripts/stop-all.sh

# 3. Удалите пакеты
sudo apt remove openvpn v2raya xray hostapd dnsmasq -y
sudo apt autoremove -y

# 4. Очистите конфиги
sudo rm -rf /etc/openvpn/client/*
sudo rm -rf /opt/anon-router/*

# 5. Переустановите
sudo bash scripts/master-install.sh
```

### Factory Reset Pi

```bash
# Полный сброс к заводским настройкам
sudo apt remove --purge openvpn* v2ray* xray* hostapd* dnsmasq* -y
sudo apt autoremove -y
sudo apt clean

# Восстановите стандартные конфиги
sudo mv /etc/dhcpcd.conf.bak /etc/dhcpcd.conf
sudo mv /etc/dnsmasq.conf.bak /etc/dnsmasq.conf
sudo mv /etc/sysctl.conf.bak /etc/sysctl.conf

# Перезагрузка
sudo reboot
```

---

## Получение помощи

Если ничего не помогло:

1. **Соберите диагностику:**
```bash
sudo /opt/anon-router/scripts/collect-diagnostics.sh
# Создаст /tmp/diagnostics.tar.gz
```

2. **Опишите проблему:**
   - Что вы пытались сделать?
   - Что произошло вместо ожидаемого?
   - Сообщения об ошибках?
   - Логи?

3. **Где искать помощь:**
   - GitHub Issues (если это был open source проект)
   - r/raspberry_pi
   - r/OpenVPN
   - Stack Overflow

---

**Большинство проблем решается перезапуском! 😄**

```bash
sudo reboot
```
