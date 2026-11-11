# 05. Создание цепочек прокси (Proxy Chain)

## 🔗 Что такое Proxy Chain?

Цепочка прокси - это последовательное подключение через несколько прокси-серверов для увеличения анонимности:

```
Клиент → Прокси 1 → Прокси 2 → Прокси 3 → Интернет
```

**Преимущества:**
- ✅ Каждый прокси видит только соседний узел
- ✅ Сложнее отследить исходный источник
- ✅ Обход блокировок на каждом уровне

**Недостатки:**
- ⚠️ Медленнее (каждый прокси добавляет задержку)
- ⚠️ Если один узел падает - вся цепь разрывается
- ⚠️ Сложнее настроить

## 🎯 Архитектура нашей цепи

> 🔑 **Ключевой принцип**: V2Ray/Proxy ВСЕГДА последний в цепочке!
> Это шифрует трафик от потенциально злонамеренных Tor exit нод!

### 🟢 Режим "Fast" (OpenVPN → V2Ray)

```
[Ты] → [WiFi] → [OpenVPN/Windscribe] → [V2Ray/Proxy] → [Интернет]
                            ↓                    ↓
                     Скрывает от ISP    Шифрует трафик
```

**Слои защиты:**
1. WiFi шифрование (WPA2)
2. OpenVPN шифрование (AES-256)
3. V2Ray шифрование (VLESS/VMess)

**Кто что видит:**
| Участник | Информация |
|----------|------------|
| ISP | VPN трафик к Windscribe |
| Windscribe | Шифрованное соединение к proxy |
| Proxy сервер | Твои запросы |

---

### 🟣 Режим "Paranoid" (OpenVPN → Tor → V2Ray) ⭐

> ⚠️ **Experimental: does not route traffic yet.** Turning "Paranoid" mode on starts the Tor service on the router, but no firewall rule sends client traffic into Tor, so traffic keeps flowing exactly as in Fast mode (lab check T1 in `docs/LAB.md`). This section describes the design target, not what the router does today. See `docs/ROADMAP.md`.

```
[Ты] → [WiFi] → [OpenVPN] → [Tor Network] → [V2Ray/Proxy] → [Интернет]
                       ↓               ↓                ↓
                  Скрывает        3 узла Tor      Шифрует от
                  от ISP что      (анонимиз.)     Tor exit node!
                  исп. Tor
```

**Слои защиты:**
1. WiFi шифрование
2. OpenVPN шифрование
3. Tor Entry Node шифрование
4. Tor Middle Node шифрование
5. Tor Exit Node → V2Ray шифрование (НЕ ВИДИТ трафик!)
6. V2Ray шифрование (VLESS/VMess)

**Кто что видит:**
| Участник | Информация |
|----------|------------|
| ISP | VPN трафик к Windscribe |
| Windscribe | Tor entry node |
| Tor exit node | ⚡ **Только шифрованный V2Ray трафик!** |
| Proxy сервер | Твои запросы (от Tor exit IP) |

> 🛡️ **Почему это безопасно**: Tor exit ноды могут прослушиваться,
> но в нашей схеме они видят только шифрованное V2Ray соединение к proxy.example.com:443!

## 🛠️ Настройка цепочки V2Ray

### Метод 1: Через v2rayA UI (простой)

1. Откройте v2rayA: http://anonrouter.local:2017

2. **Добавьте несколько серверов:**
   - Нажмите "Import"
   - Добавьте Server 1: `vless://uuid1@server1.com:443?...`
   - Добавьте Server 2: `vmess://base64string...`
   - Добавьте Server 3: `ss://base64string...`

3. **Создайте цепочку:**
   - Выберите Server 1 (Ctrl+Click)
   - Выберите Server 2 (Hold Ctrl)
   - Выберите Server 3 (Hold Ctrl)
   - Правый клик → "Create Chain"

4. **Выберите цепочку:**
   - В списке появится "Chain: Server1→Server2→Server3"
   - Выберите эту цепочку
   - Нажмите "Start"

5. **Проверка:**
```bash
curl ipinfo.io
# Должен показать IP последнего сервера в цепи (Server 3)
```

### Метод 2: Ручная конфигурация (продвинутый)

Создайте конфигурационный файл с цепочкой:

```bash
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
      "tag": "proxy-chain",
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": "final-server.com",
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
        "network": "ws",
        "security": "tls",
        "wsSettings": {
          "path": "/v2ray"
        }
      },
      "proxySettings": {
        "tag": "proxy-1"
      }
    },
    {
      "tag": "proxy-1",
      "protocol": "vmess",
      "settings": {
        "vnext": [
          {
            "address": "middle-server.com",
            "port": 443,
            "users": [
              {
                "id": "middle-uuid",
                "alterId": 0
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
      "protocol": "freedom"
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
        "outboundTag": "proxy-chain"
      }
    ]
  }
}
```

**Объяснение конфига:**
- `proxy-chain` → идет через `proxy-1`
- `proxy-1` → идет напрямую в интернет
- Результат: трафик идет через 2 прокси последовательно

### Запуск с кастомным конфигом:

```bash
# Остановите v2rayA
sudo systemctl stop v2raya

# Запустите с кастомным конфигом
sudo xray run -c /opt/shadowpi/configs/v2ray-chain.json

# Или создайте systemd сервис
sudo nano /etc/systemd/system/xray-chain.service
```

```ini
[Unit]
Description=XRay Proxy Chain
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/xray run -c /opt/shadowpi/configs/v2ray-chain.json
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable xray-chain
sudo systemctl start xray-chain
```

---

## 🏠 Резидентные SOCKS5 прокси с авторизацией

> [!TIP]
> Резидентные прокси выглядят как обычные домашние пользователи — идеально для обхода блокировок!

### Формат прокси

Многие провайдеры дают прокси в формате:
```
host:port:username:password
```

**Пример:**
```
resident.proxyshard.com:1080:user-country-us-region-arizona:password123
```

### V2Ray конфигурация для SOCKS5 с авторизацией

> [!IMPORTANT]
> **Proxychains плохо работает с доменами** — используйте V2Ray!

```bash
sudo nano /opt/shadowpi/configs/v2ray-residential.json
```

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
    },
    {
      "tag": "socks-local",
      "port": 10808,
      "listen": "0.0.0.0",
      "protocol": "socks",
      "settings": {
        "udp": true
      }
    }
  ],
  "outbounds": [
    {
      "tag": "residential-proxy",
      "protocol": "socks",
      "settings": {
        "servers": [
          {
            "address": "resident.proxyshard.com",
            "port": 1080,
            "users": [
              {
                "user": "YOUR_USERNAME",
                "pass": "YOUR_PASSWORD"
              }
            ]
          }
        ]
      }
    },
    {
      "tag": "direct",
      "protocol": "freedom"
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
        "inboundTag": ["transparent", "socks-local"],
        "outboundTag": "residential-proxy"
      }
    ]
  }
}
```

### Преимущества резидентных прокси

| Параметр | Datacenter Proxy | Residential Proxy |
|----------|------------------|-------------------|
| IP тип | Серверный | Домашний ISP ✅ |
| Обнаружение | Легко | Сложно ✅ |
| Блокировки | Часто | Редко ✅ |
| Цена | Дешевле | Дороже |

### Проверка подключения

```bash
# Через локальный SOCKS порт V2Ray
curl -x socks5://127.0.0.1:10808 https://ipinfo.io

# Должен показать резидентный IP провайдера
```

---

## 🔥 Настройка цепи OpenVPN → V2Ray → Tor

> ⚠️ **Experimental: does not route traffic yet.** Turning "Paranoid" mode on starts the Tor service on the router, but no firewall rule sends client traffic into Tor, so traffic keeps flowing exactly as in Fast mode (lab check T1 in `docs/LAB.md`). This section describes the design target, not what the router does today. See `docs/ROADMAP.md`.

### Шаг 1: Убедитесь что OpenVPN и V2Ray работают

```bash
sudo systemctl status openvpn-windscribe
sudo systemctl status v2raya
```

### Шаг 2: Настройте Tor

```bash
sudo nano /etc/tor/torrc
```

Вставьте:

```conf
# Tor Configuration
SocksPort 9050
SocksPolicy accept 10.0.0.0/24
SocksPolicy accept 127.0.0.1

DNSPort 5353
TransPort 9040

VirtualAddrNetworkIPv4 10.192.0.0/10
AutomapHostsOnResolve 1

# Performance
CircuitBuildTimeout 30
LearnCircuitBuildTimeout 0
MaxCircuitDirtiness 600

# Logging
Log notice file /var/log/tor/notices.log
```

### Шаг 3: Запустите Tor

```bash
sudo mkdir -p /var/log/tor
sudo chown debian-tor:debian-tor /var/log/tor

sudo systemctl enable tor
sudo systemctl start tor

# Проверка
sudo systemctl status tor
```

### Шаг 4: Настройте маршрутизацию через Tor

```bash
sudo nano /opt/shadowpi/scripts/route-through-tor.sh
```

```bash
#!/bin/bash
# Route traffic: V2Ray -> OpenVPN -> Tor

# Tor transparent proxy
iptables -t nat -A OUTPUT -p tcp --dport 80 -j REDIRECT --to-ports 9040
iptables -t nat -A OUTPUT -p tcp --dport 443 -j REDIRECT --to-ports 9040

# DNS через Tor
iptables -t nat -A OUTPUT -p udp --dport 53 -j REDIRECT --to-ports 5353

echo "✅ Routing через Tor активирован"
```

```bash
sudo chmod +x /opt/shadowpi/scripts/route-through-tor.sh
sudo /opt/shadowpi/scripts/route-through-tor.sh
```

### Шаг 5: Проверка полной цепи

```bash
# Обычный IP (должен быть VPN)
curl ipinfo.io

# IP через Tor
curl --socks5 127.0.0.1:9050 ipinfo.io

# Должны быть РАЗНЫЕ!

# Проверка цепочки
curl --socks5 127.0.0.1:9050 https://check.torproject.org/api/ip
# Должен вернуть: {"IsTor":true,"IP":"xxx.xxx.xxx.xxx"}
```

## 📊 Сравнение режимов

| Режим | Скорость | Анонимность | Сложность |
|-------|----------|-------------|-----------|
| Только VPN | ⚡⚡⚡⚡⚡ | 🔒🔒 | ⭐ |
| VPN + V2Ray | ⚡⚡⚡⚡ | 🔒🔒🔒 | ⭐⭐ |
| V2Ray Chain (2-3) | ⚡⚡⚡ | 🔒🔒🔒🔒 | ⭐⭐⭐ |
| VPN + V2Ray + Tor | ⚡ | 🔒🔒🔒🔒🔒 | ⭐⭐⭐⭐ |

## 🎛️ Управление цепочками

### Скрипт переключения режимов

```bash
sudo nano /opt/shadowpi/scripts/switch-mode.sh
```

```bash
#!/bin/bash

MODE=$1

case $MODE in
  basic)
    echo "🔵 Режим: VPN only"
    sudo systemctl stop v2raya tor
    sudo systemctl start openvpn-windscribe
    ;;
  
  standard)
    echo "🟢 Режим: VPN + V2Ray"
    sudo systemctl stop tor
    sudo systemctl start openvpn-windscribe v2raya
    ;;
  
  advanced)
    echo "🟣 Режим: VPN + V2Ray + Tor"
    sudo systemctl start openvpn-windscribe v2raya tor
    sudo /opt/shadowpi/scripts/route-through-tor.sh
    ;;
  
  *)
    echo "Usage: $0 {basic|standard|advanced}"
    exit 1
    ;;
esac

sleep 3
curl ipinfo.io
```

```bash
sudo chmod +x /opt/shadowpi/scripts/switch-mode.sh

# Использование:
sudo /opt/shadowpi/scripts/toggle-tor.sh fast      # Режим Fast (VPN → Proxy)
sudo /opt/shadowpi/scripts/toggle-tor.sh paranoid  # Режим Paranoid (VPN → Tor → Proxy)
sudo /opt/shadowpi/scripts/toggle-tor.sh toggle    # Переключить
```

## 🧪 Тестирование цепочки

```bash
# Тест каждого узла
echo "=== Testing Proxy Chain ==="

echo "1. Direct IP (no proxy):"
curl -s --interface eth0 ipinfo.io/ip

echo "2. Through VPN:"
curl -s ipinfo.io/ip

echo "3. Through V2Ray (via tproxy):"
curl -s --interface wlan0 ipinfo.io/ip

echo "4. Through Tor (if enabled):"
curl -s --socks5 127.0.0.1:9050 ipinfo.io/ip

echo "=== All IPs should be different! ==="
```

## 🔒 Безопасность цепочек

### Важные правила:

1. **Никогда не логируйтесь** на личные аккаунты через Tor
2. **Используйте разные серверы** в разных странах
3. **Не доверяйте одному провайдеру** - mix разных VPN/прокси
4. **Проверяйте DNS leaks** после каждого изменения
5. **Tor + VPN вместе** могут привлечь внимание

### Killswitch для цепочки:

```bash
# Если любой узел падает - блокировать весь трафик
sudo nano /etc/systemd/system/openvpn-windscribe.service

# Добавьте в [Service]:
ExecStopPost=/opt/shadowpi/scripts/killswitch.sh
```

## 💡 Лучшие практики

### Для максимальной скорости:
- Используйте 1-2 прокси максимум
- Выбирайте серверы близко географически
- Используйте VLESS или Shadowsocks (быстрее VMess)

### Для максимальной анонимности:
- Используйте режим Paranoid (VPN → Tor → Proxy)
- V2Ray/Proxy всегда в конце цепочки (шифрует от Tor exit)
- Используйте разных провайдеров
- Регулярно меняйте серверы

### Для обхода блокировок:
- Первый прокси в свободной стране
- Используйте WebSocket или gRPC (маскируется под HTTPS)
- Включите traffic obfuscation

## ✅ Готово!

Теперь у вас есть гибкая система цепочек прокси!

**Следующий шаг:** `06_WIFI_HOTSPOT.md` - детальная настройка WiFi
