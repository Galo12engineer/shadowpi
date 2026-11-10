# 04. Настройка V2Ray/XRay с v2rayA

v2rayA - это веб-интерфейс для V2Ray/XRay, аналог v2rayN для Windows. Позволяет:
- Добавлять прокси серверы (VLESS, VMess, Shadowsocks, Trojan, SOCKS)
- Импортировать подписки (subscriptions)
- Создавать цепочки прокси
- Transparent proxy для всего трафика

## Шаг 1: Проверка установки v2rayA

```bash
# SSH на Pi
ssh admin@anonrouter.local

# Проверьте статус v2rayA
sudo systemctl status v2raya

# Проверьте XRay
xray version

# Должно быть: Xray 1.8.x или новее
```

## Шаг 2: Первый вход в веб-интерфейс

```bash
# Откройте браузер на вашем компьютере:
# http://anonrouter.local:2017

# Или если не работает, используйте IP:
# http://192.168.1.X:2017

# При первом входе нужно создать админ аккаунт:
# Username: admin
# Password: [ваш_пароль] (запомните его!)
```

## Шаг 3: Настройка v2rayA через Web UI

### 3.1. Добавление прокси-сервера вручную

В веб-интерфейсе:

1. **Servers** → **Create**
2. Выберите тип протокола:
   - VLESS (рекомендуется, самый новый)
   - VMess (популярный)
   - Shadowsocks (простой, быстрый)
   - Trojan (маскируется под HTTPS)
   - SOCKS5 (обычный прокси)

3. Введите параметры сервера:
   ```
   Address: your-proxy-server.com
   Port: 443
   UUID/Password: [ваш ключ]
   Security: auto
   Network: tcp (или ws для WebSocket)
   ```

4. **Save**

### 3.2. Импорт подписки (Subscriptions)

Если у вас есть ссылка на подписку (subscription URL):

1. **Setting** → **Subscription**
2. **Add Subscription**
3. Вставьте URL подписки:
   ```
   https://example.com/subscribe?token=xxx
   ```
4. **Update Subscription**

Все серверы из подписки автоматически добавятся!

### 3.3. Импорт через ссылку

Если у вас есть прямая ссылка вида:
```
vless://uuid@server:port?...
vmess://base64string...
ss://base64string...
```

1. **Servers** → **Import**
2. Вставьте ссылку
3. **Import**

## Шаг 4: Настройка Transparent Proxy

Это ключевая настройка для маршрутизации всего трафика через V2Ray!

В веб-интерфейсе:

1. **Setting** → **Transparent Proxy / System Proxy**
2. Выберите режим:
   - **tproxy** (рекомендуется для роутера)
   - Или **redirect** (если tproxy не работает)

3. **Transparent Proxy Port**: `12345` (по умолчанию)
4. **Listening IP**: `0.0.0.0` (слушать на всех интерфейсах)

5. **Включите:**
   - ✅ Start on boot
   - ✅ Transparent proxy for LAN

6. **Save and Apply**

## Шаг 5: Настройка маршрутизации (Routing)

Это настройка цепочки: OpenVPN → V2Ray

В веб-интерфейсе:

1. **Setting** → **Routing**

2. **Default Outbound**: Выберите ваш прокси-сервер

3. **Advanced Routing Rules** (опционально):
   ```json
   {
     "rules": [
       {
         "type": "field",
         "outboundTag": "proxy",
         "domain": ["geosite:category-ads"],
         "enabled": false
       },
       {
         "type": "field",
         "outboundTag": "direct",
         "ip": ["geoip:private"],
         "enabled": true
       }
     ]
   }
   ```

   Это будет:
   - Локальные IP (192.168.x.x) → напрямую (не через прокси)
   - Все остальное → через прокси → через OpenVPN

## Шаг 6: Настройка цепочки через конфигурационный файл

Для продвинутой настройки цепочки VPN → V2Ray:

```bash
# Создайте кастомный конфиг для цепочки
sudo mkdir -p /opt/shadowpi/configs

sudo nano /opt/shadowpi/configs/v2ray-chain.json
```

Вставьте:

```json
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "tag": "transparent",
      "port": 12345,
      "protocol": "dokodemo-door",
      "settings": {
        "network": "tcp,udp",
        "followRedirect": true
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      }
    }
  ],
  "outbounds": [
    {
      "tag": "proxy",
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": "your-server.com",
            "port": 443,
            "users": [
              {
                "id": "your-uuid-here",
                "encryption": "none"
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "tls"
      }
    },
    {
      "tag": "direct",
      "protocol": "freedom",
      "settings": {}
    },
    {
      "tag": "block",
      "protocol": "blackhole",
      "settings": {}
    }
  ],
  "routing": {
    "rules": [
      {
        "type": "field",
        "ip": ["geoip:private"],
        "outboundTag": "direct"
      },
      {
        "type": "field",
        "outboundTag": "proxy"
      }
    ]
  }
}
```

**ВАЖНО**: Замените `your-server.com` и `your-uuid-here` на ваши данные!

```bash
# Используйте этот конфиг (опционально, если нужна точная настройка)
# sudo systemctl stop v2raya
# sudo xray run -c /opt/shadowpi/configs/v2ray-chain.json
```

## Шаг 7: Настройка iptables для перенаправления трафика

V2Ray нужно перенаправить весь трафик с WiFi (wlan0) в transparent proxy:

Скрипт уже лежит в репозитории (`scripts/setup-v2ray-redirect.sh`), установщик кладёт его
в `/opt/shadowpi/scripts/`. Не создавайте свою копию — правьте файл в репозитории.

Что он делает:
- перенаправляет TCP клиентов Wi-Fi на порт `12345` (inbound `dokodemo-door` из шага выше);
- **не трогает** соединения к самому роутеру (панель, DNS, SSH) и частные сети —
  отбор по адресу назначения, а не по порту, иначе веб (80/443) шёл бы мимо прокси;
- открывает порт `12345` в INPUT для `wlan0`, потому что killswitch по умолчанию режет входящие;
- **отказывается** включаться, если на `12345` никто не слушает: иначе у клиентов
  умрёт весь TCP, кроме того, что не перенаправляется. Тогда трафик идёт только через VPN.

```bash
sudo /opt/shadowpi/scripts/setup-v2ray-redirect.sh       # включить
sudo /opt/shadowpi/scripts/setup-v2ray-redirect.sh off   # выключить
```

Важно: inbound должен слушать не только `127.0.0.1` (`"listen": "0.0.0.0"` или адрес `wlan0`),
потому что REDIRECT доставляет соединения на адрес интерфейса, с которого они пришли.

## Шаг 8: Автозапуск v2rayA с правильными приоритетами

```bash
# Убедитесь что v2rayA запускается ПОСЛЕ OpenVPN
sudo nano /etc/systemd/system/v2raya.service.d/override.conf
```

Создайте папку если нужно:
```bash
sudo mkdir -p /etc/systemd/system/v2raya.service.d
sudo nano /etc/systemd/system/v2raya.service.d/override.conf
```

Вставьте:

```ini
[Unit]
After=openvpn-windscribe.service
Wants=openvpn-windscribe.service

[Service]
Restart=on-failure
RestartSec=5
```

```bash
# Перезагрузите конфиги
sudo systemctl daemon-reload

# Перезапустите v2rayA
sudo systemctl restart v2raya

# Проверьте
sudo systemctl status v2raya
```

## Шаг 9: Тестирование цепочки

```bash
# Запустите всю цепочку
sudo systemctl start openvpn-windscribe
sudo systemctl start v2raya

# Подождите 10 секунд для подключения

# Проверьте IP
curl ipinfo.io

# Должен показать IP вашего V2Ray прокси-сервера!

# Проверьте маршрут
traceroute -T ipinfo.io

# Должно быть:
# 1. Ваш роутер
# 2. VPN сервер
# 3. Прокси сервер
# 4. Целевой сервер
```

## Шаг 10: Создание цепочек (chaining)

В v2rayA можно создать несколько прокси друг за другом:

1. В веб-интерфейсе: **Servers**
2. Выберите несколько серверов (Ctrl+Click)
3. **Create Chain**
4. Серверы будут работать цепочкой!

Например:
```
Клиент → Server 1 (Shadowsocks) → Server 2 (VMess) → Internet
```

Это добавит дополнительный слой анонимности!

## 🔧 Управление v2rayA

```bash
# Запуск
sudo systemctl start v2raya

# Остановка
sudo systemctl stop v2raya

# Перезапуск
sudo systemctl restart v2raya

# Статус
sudo systemctl status v2raya

# Логи
sudo journalctl -u v2raya -f
```

## 📊 Проверка работы transparent proxy

```bash
# Проверьте что порт 12345 слушается
sudo netstat -tlnp | grep 12345

# Должно показать xray или v2ray слушает на :12345

# Проверьте iptables правила
sudo iptables -t nat -L V2RAY -n -v

# Должны быть правила для редиректа
```

## 🐛 Troubleshooting

### v2rayA не стартует

```bash
# Проверьте логи
sudo journalctl -u v2raya -n 50

# Часто проблема в конфликте портов
# Убедитесь что порт 2017 свободен:
sudo netstat -tlnp | grep 2017
```

### Transparent proxy не работает

```bash
# Проверьте что v2rayA в режиме tproxy
# Веб-интерфейс → Setting → Transparent Proxy: tproxy

# Проверьте iptables правила
sudo iptables -t nat -L -n -v

# Перезапустите скрипт редиректа
sudo /opt/shadowpi/scripts/setup-v2ray-redirect.sh
```

### Медленная скорость

```bash
# 1. Используйте VLESS вместо VMess (быстрее)
# 2. Включите mux (multiplexing) в настройках сервера
# 3. Попробуйте другой прокси-сервер ближе к вам
# 4. В v2rayA: Setting → Advanced → Enable XTLS
```

## ✅ Готово!

V2Ray/XRay настроен с веб-интерфейсом! Переходите к **05_PROXY_CHAIN.md**

## 📝 Что сделано:

- ✅ v2rayA веб-интерфейс доступен на порту 2017
- ✅ XRay core установлен
- ✅ Transparent proxy настроен (порт 12345)
- ✅ iptables правила для редиректа трафика
- ✅ Поддержка VLESS, VMess, Shadowsocks, Trojan, SOCKS
- ✅ Импорт подписок
- ✅ Создание цепочек прокси
- ✅ Интеграция с OpenVPN
