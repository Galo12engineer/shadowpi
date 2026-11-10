# 10. Тестирование и проверка безопасности

## Автоматическое тестирование

Запустите комплексный тест всех компонентов:

```bash
ssh admin@anonrouter.local

# Запуск всех тестов
sudo bash /opt/shadowpi/scripts/test-all.sh
```

Этот скрипт проверит:
- ✅ Публичный IP (должен быть VPN/прокси)
- ✅ DNS утечки (DNS leak)
- ✅ IPv6 утечки
- ✅ WebRTC утечки
- ✅ Статус всех сервисов
- ✅ Скорость соединения
- ✅ Firewall правила
- ✅ Открытые порты

## Ручное тестирование

### 1. Проверка IP адреса

```bash
# Базовая проверка IP
curl ipinfo.io

# Детальная информация
curl ipinfo.io/json | jq

# Должно показать:
# - IP: IP вашего VPN/прокси сервера
# - Location: Страну сервера (НЕ вашу!)
# - Org: Провайдера VPN/прокси
```

**Ожидаемый результат:**
```json
{
  "ip": "185.xxx.xxx.xxx",
  "city": "Amsterdam",
  "country": "NL",
  "org": "AS54290 Windscribe Limited"
}
```

### 2. DNS Leak Test

```bash
# Проверка DNS серверов
dig +short whoami.akamai.net @resolver1.opendns.com

# Альтернативная проверка
nslookup -type=txt whoami.akamai.net resolver1.opendns.com

# DNS должен совпадать с VPN IP!
```

**Онлайн тесты:**
- https://dnsleaktest.com - Extended Test
- https://www.dnsleaktest.org

### 3. IPv6 Leak Test

```bash
# Проверка IPv6
curl -6 ifconfig.co

# Должна быть ошибка или пустой ответ (IPv6 отключен)

# Проверка системных настроек
cat /proc/sys/net/ipv6/conf/all/disable_ipv6
# Должно быть: 1
```

**Онлайн тест:**
- https://ipv6leak.com

### 4. WebRTC Leak Test

WebRTC может раскрыть ваш настоящий IP через браузер!

**Тест в браузере:**
1. На устройстве подключенном к WiFi hotspot
2. Откройте: https://browserleaks.com/webrtc
3. Проверьте что показывается только VPN IP

**Защита:**
- Firefox: `about:config` → `media.peerconnection.enabled` → `false`
- Chrome: Установите расширение "WebRTC Leak Shield"

### 5. Торрент IP Test (для продвинутых)

```bash
# ТОЛЬКО ДЛЯ ТЕСТА! Не качайте копирайт контент!

# 1. Откройте https://ipleak.net на клиенте
# 2. Скачайте магнет-ссылку для теста
# 3. Добавьте в торрент-клиент
# 4. Проверьте какой IP показывается
```

### 6. Проверка всей цепочки (Traceroute)

```bash
# Traceroute для проверки маршрута
traceroute -T google.com

# Должно быть примерно так:
# 1. 10.0.0.1 (ваш Pi роутер)
# 2. 10.x.x.x (VPN туннель)
# 3. VPN сервер
# 4. Прокси сервер (может не показываться)
# 5. Целевой сервер
```

### 7. Port Scan (проверка открытых портов)

```bash
# Внешний скан ваших портов
curl "https://api.hackertarget.com/nmap/?q=$(curl -s ipinfo.io/ip)"

# Большинство портов должны быть closed/filtered

# Локальная проверка
sudo nmap -sT -p- localhost
```

### 8. Speed Test

```bash
# Простой тест
speedtest-cli

# Или онлайн
curl -s https://raw.githubusercontent.com/sivel/speedtest-cli/master/speedtest.py | python3 -
```

**Нормальные скорости:**
- OpenVPN: 50-150 Mbps (зависит от сервера)
- V2Ray overhead: ~5-10%
- С Tor: значительно медленнее (10-30 Mbps)

### 9. Проверка killswitch

Killswitch должен блокировать весь трафик если VPN упал.

```bash
# Остановите VPN
sudo systemctl stop openvpn-windscribe

# Попробуйте подключиться к интернету
curl ipinfo.io

# Должна быть ошибка! Если показывает ваш реальный IP - killswitch НЕ работает!

# Восстановите VPN
sudo systemctl start openvpn-windscribe
```

## Онлайн тесты (полный набор)

Откройте эти сайты на устройстве подключенном к WiFi hotspot:

### Общие тесты утечек
1. **https://ipleak.net** - Лучший комплексный тест
   - IP leak
   - DNS leak
   - WebRTC leak
   - Торрент leak

2. **https://browserleaks.com** - Детальные тесты браузера
   - WebRTC
   - JavaScript
   - Canvas fingerprinting
   - Font fingerprinting

3. **https://whoer.net** - Оценка анонимности
   - Выставляет оценку вашей анонимности
   - Показывает что нужно исправить

### DNS тесты
4. **https://dnsleaktest.com** - Стандартный DNS тест
5. **https://www.dnsleaktest.org** - Альтернативный DNS тест

### IPv6 тесты
6. **https://ipv6leak.com** - Проверка IPv6

### Geolocation тесты
7. **https://www.geodatatool.com** - Показывает вашу геолокацию
8. **https://ipinfo.io** - IP информация

### Fingerprinting
9. **https://amiunique.org** - Browser fingerprinting
10. **https://coveryourtracks.eff.org** - EFF Privacy test

## Тестирование с разных устройств

### Windows/Mac/Linux (Laptop)
```bash
# Подключитесь к WiFi "ShadowPi"
# Откройте терминал/PowerShell

# Windows PowerShell:
Invoke-RestMethod ipinfo.io/json | ConvertTo-Json

# Mac/Linux:
curl ipinfo.io/json | jq
```

### Android
1. Подключитесь к WiFi hotspot
2. Установите "Net Analyzer" из Play Store
3. Проверьте ваш публичный IP
4. Откройте https://ipleak.net в браузере

### iOS (iPhone/iPad)
1. Подключитесь к WiFi hotspot
2. Откройте Safari → https://ipleak.net
3. Проверьте все тесты

## Расширенное тестирование

### Pentest инструменты

```bash
# SSH на Pi
ssh admin@anonrouter.local

# Установка инструментов
sudo apt install -y nmap wireshark-cli tcpdump

# Сканирование сети
sudo nmap -sn 10.0.0.0/24

# Мониторинг трафика
sudo tcpdump -i wlan0 -n

# Проверка DNS запросов
sudo tcpdump -i any port 53 -v
```

### Проверка цепочки прокси

```bash
# Проверьте что трафик идет через все узлы

# 1. Публичный IP (должен быть прокси)
curl ipinfo.io/ip

# 2. Через SOCKS5 прокси напрямую (если настроен)
curl --socks5 127.0.0.1:10808 ipinfo.io/ip

# 3. Через Tor (если включен)
curl --socks5 127.0.0.1:9050 ipinfo.io/ip

# Все три должны показывать РАЗНЫЕ IP!
```

### Stress Test (нагрузочное тестирование)

```bash
# Тест пропускной способности
iperf3 -c speedtest.serverius.net -p 5002

# Множественные соединения
ab -n 1000 -c 10 http://example.com/

# Мониторинг во время теста
htop
iftop -i wlan0
```

## Проверка логов

```bash
# OpenVPN логи
sudo tail -f /var/log/openvpn/openvpn.log

# v2rayA логи
sudo journalctl -u v2raya -f

# Системные логи
sudo journalctl -f

# dmesg для ошибок ядра
sudo dmesg | tail -50
```

## Benchmark результаты

**Нормальные показатели для Raspberry Pi 4:**

| Конфигурация | Download | Upload | Latency |
|--------------|----------|--------|---------|
| Прямое подключение | 300+ Mbps | 300+ Mbps | 10-20ms |
| Только OpenVPN | 80-150 Mbps | 50-100 Mbps | 30-60ms |
| OpenVPN + V2Ray | 60-120 Mbps | 40-80 Mbps | 50-100ms |
| OpenVPN + V2Ray + Tor | 10-30 Mbps | 5-20 Mbps | 200-500ms |

**Температура:**
- Idle: 40-50°C
- Под нагрузкой: 60-70°C
- Критично: >80°C (нужно охлаждение!)

## Checklist перед использованием

Перед тем как использовать роутер в реальных условиях:

- [ ] Публичный IP НЕ ваш реальный
- [ ] DNS тест пройден (no leaks)
- [ ] IPv6 отключен
- [ ] WebRTC не утекает IP
- [ ] Killswitch работает
- [ ] Все сервисы запущены (VPN, V2Ray, WiFi)
- [ ] Скорость приемлемая (>10 Mbps)
- [ ] Температура Pi <70°C
- [ ] Веб-панель доступна
- [ ] Логи не показывают ошибок

## Если что-то не работает

Смотрите **11_TROUBLESHOOTING.md** для решения проблем!

## Регулярные проверки

Рекомендуется проверять систему:
- **Ежедневно**: IP адрес и статус сервисов
- **Еженедельно**: DNS leak test
- **Ежемесячно**: Полный тест всех компонентов
- **После обновлений**: Полное тестирование

```bash
# Добавьте в cron для ежедневной проверки
echo "0 8 * * * /opt/shadowpi/scripts/test-all.sh > /var/log/shadowpi/daily-test.log 2>&1" | sudo crontab -
```

## ✅ Ваша система безопасна если:

1. ✅ Публичный IP != Ваш реальный IP
2. ✅ DNS серверы = VPN DNS
3. ✅ IPv6 полностью отключен
4. ✅ WebRTC показывает только VPN IP
5. ✅ Killswitch блокирует при отключении VPN
6. ✅ Нет открытых портов снаружи
7. ✅ Все тесты на ipleak.net зеленые

**Наслаждайтесь приватностью и свободой! 🔒🌐**
