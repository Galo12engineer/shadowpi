# Архитектура проекта

## 📋 Структура проекта

```
shadowpi/
│
├── README.md                      # Главная документация
├── QUICKSTART.md                  # Быстрый старт (30 минут)
│
├── docs/                          # Подробная документация
│   ├── 01_OS_INSTALLATION.md      # Установка ОС
│   ├── 02_BASE_PACKAGES.md        # Установка пакетов
│   ├── 03_OPENVPN_SETUP.md        # Настройка OpenVPN
│   ├── 04_V2RAY_SETUP.md          # Настройка V2Ray/XRay
│   ├── 05_PROXY_CHAIN.md          # Создание цепочек прокси
│   ├── 06_WIFI_HOTSPOT.md         # WiFi Hotspot настройка
│   ├── 07_4G_MODEM.md             # USB 4G/LTE модемы
│   ├── 08_FIREWALL.md             # Firewall и killswitch
│   ├── 09_WEB_UI.md               # Веб-панель управления
│   ├── 10_TESTING.md              # Тестирование безопасности
│   └── 11_TROUBLESHOOTING.md      # Решение проблем
│
├── scripts/                       # Скрипты автоматизации
│   ├── master-install.sh          # Мастер установки (все в одном)
│   ├── start-all.sh               # Запустить все сервисы
│   ├── stop-all.sh                # Остановить все сервисы
│   ├── restart-all.sh             # Перезапустить все
│   ├── toggle-tor.sh              # Вкл/выкл Tor
│   ├── test-all.sh                # Тесты безопасности
│   └── setup-v2ray-redirect.sh    # iptables для V2Ray
│
├── web-ui/                        # Веб-панель управления
│   ├── index.html                 # Главная страница
│   ├── style.css                  # Стили (dark theme)
│   ├── app.js                     # JavaScript логика
│   └── api.php                    # Backend API
│
└── configs/                       # Примеры конфигураций
    ├── openvpn/                   # OpenVPN конфиги
    ├── v2ray/                     # V2Ray конфиги
    ├── hostapd/                   # WiFi Hotspot конфиги
    └── firewall/                  # nftables правила
```

## 🌐 Источники интернета (WAN)

ShadowPi поддерживает несколько способов подключения к интернету:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        ИСТОЧНИКИ ИНТЕРНЕТА (WAN)                            │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  🔌 Ethernet (eth0)      📡 4G/LTE Modem (wwan0)     📶 WiFi Client (wlan1) │
│  ─────────────────       ─────────────────────       ─────────────────────  │
│  • Провод от роутера     • USB модем Huawei E3372    • USB WiFi адаптер     │
│  • Самый надёжный        • ZTE MF79U, MF833V         • Подключение к        │
│  • Gigabit скорость      • Мобильный интернет        • существующему WiFi   │
│                          • Автономный режим          • Не рекомендуется     │
│                                                                             │
│  🔗 USB Ethernet         🔄 Fail-over режим                                 │
│  ─────────────────       ─────────────────────                              │
│  • USB-C/USB-A донглы    • Автопереключение                                 │
│  • Второй порт LAN       • Ethernet ↔ 4G                                    │
│                          • Резервный канал                                  │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ↓
                         ┌────────────────────────┐
                         │   🍓 Raspberry Pi      │
                         │   ShadowPi Router      │
                         └────────────────────────┘
```

### Рекомендуемые варианты:

| Источник | Интерфейс | Скорость | Надёжность | Применение |
|----------|-----------|----------|------------|------------|
| **🔌 Ethernet** | eth0 | ⚡⚡⚡⚡⚡ | ⭐⭐⭐⭐⭐ | Дома, офис |
| **📡 4G/LTE модем** | wwan0 | ⚡⚡⚡ | ⭐⭐⭐⭐ | Мобильный, автономный |
| **🔗 USB Ethernet** | eth1 | ⚡⚡⚡⚡⚡ | ⭐⭐⭐⭐⭐ | Второй провод, fail-over |
| **📶 WiFi Client** | wlan1 | ⚡⚡⚡ | ⭐⭐⭐ | Не рекомендуется* |

> ⚠️ *WiFi Client (wlan1) требует дополнительный USB WiFi адаптер, так как встроенный wlan0 используется как Hotspot

### Поддерживаемые 4G/LTE модемы:

- ✅ **Huawei E3372h-320** — рекомендуемый, режим HiLink
- ✅ **Huawei E3372s** — режим Stick
- ✅ **ZTE MF79U** — WiFi + USB режим
- ✅ **ZTE MF833V** — USB режим
- ✅ **Alcatel IK40V** — бюджетный вариант
- ✅ Большинство модемов с поддержкой ModemManager

---

## 🔄 Поток данных (Data Flow)

### 🟢 Режим "Fast" (по умолчанию)

```
┌─────────────────────────────────────────────────────────────────┐
│   📱 Телефон    💻 Ноутбук    🖥️ ПК    🎮 Консоль             │
└──────────────────────────────┬──────────────────────────────────┘
                               │ WiFi (WPA2)
                               ↓
                    ┌─────────────────────────┐
                    │  🍓 Raspberry Pi      │
                    │  wlan0: 10.0.0.1      │
                    └────────────┬────────────┘
                               │
                               ↓
                    ┌─────────────────────────┐
                    │  1️⃣ OpenVPN (tun0)   │
                    │  Windscribe VPN       │
                    └────────────┬────────────┘
                               │
                               ↓
                    ┌─────────────────────────┐
                    │  2️⃣ V2Ray/XRay       │  ← ПОСЛЕДНИЙ!
                    │  VLESS/VMess Proxy    │
                    └────────────┬────────────┘
                               │
                               ↓
                        ☁️ INTERNET ☁️
```

### 🟣 Режим "Paranoid" (+ Tor)

> ⚠️ **What Paranoid mode really does.** Client TCP and DNS go through Tor, and Tor itself goes out through the VPN tunnel (lab checks T1, T3 and T4 in `docs/LAB.md`). Other client traffic (UDP, ICMP) is dropped. The V2Ray hop **after** Tor described in this section is **not implemented**: the Tor exit node sees the traffic like any other Tor exit does. See `docs/ROADMAP.md`.

```
┌─────────────────────────────────────────────────────────────────┐
│   📱 Телефон    💻 Ноутбук    🖥️ ПК    🎮 Консоль             │
└──────────────────────────────┬──────────────────────────────────┘
                               │ WiFi (WPA2)
                               ↓
                    ┌─────────────────────────┐
                    │  🍓 Raspberry Pi      │
                    │  wlan0: 10.0.0.1      │
                    └────────────┬────────────┘
                               │
                               ↓
                    ┌─────────────────────────┐
                    │  1️⃣ OpenVPN (tun0)   │
                    │  Windscribe VPN       │
                    └────────────┬────────────┘
                               │
                               ↓
                    ┌─────────────────────────┐
                    │  2️⃣ Tor Network      │
                    │  SOCKS5: 9050         │
                    │  Entry → Middle → Exit│
                    └────────────┬────────────┘
                               │
                               ↓
                    ┌─────────────────────────┐
                    │  3️⃣ V2Ray/XRay       │  ← ПОСЛЕДНИЙ!
                    │  VLESS/VMess Proxy    │
                    │  🔒 Шифрует от Tor!   │
                    └────────────┬────────────┘
                               │
                               ↓
                        ☁️ INTERNET ☁️
```

## 🔐 Цепочка анонимности

### 🟢 Режим "Fast" (OpenVPN → V2Ray)

```
[Ты] → [OpenVPN/Windscribe] → [V2Ray Proxy] → [Интернет]
         ↓                      ↓               ↓
      Скрывает от ISP     Шифрует трафик   Виден IP прокси
```

**Кто что видит:**
| Участник | Информация |
|----------|------------|
| **ISP** | VPN трафик к Windscribe |
| **Windscribe** | Шифрованное соединение к прокси серверу |
| **Прокси сервер** | Твои запросы |

✅ Быстро, надёжно  
⚠️ Прокси видит трафик, Windscribe знает твой IP

---

### 🟣 Режим "Paranoid" (OpenVPN → Tor → V2Ray)

> ⚠️ **What Paranoid mode really does.** Client TCP and DNS go through Tor, and Tor itself goes out through the VPN tunnel (lab checks T1, T3 and T4 in `docs/LAB.md`). Other client traffic (UDP, ICMP) is dropped. The V2Ray hop **after** Tor described in this section is **not implemented**: the Tor exit node sees the traffic like any other Tor exit does. See `docs/ROADMAP.md`.

```
[Ты] → [OpenVPN] → [Tor Network] → [V2Ray Proxy] → [Интернет]
         ↓                ↓                ↓
      Скрывает       3 узла Tor      Шифрует от Tor exit!
      от ISP что      (аноним.)       🔐 Exit нода НЕ видит
      исп. Tor                        твой трафик!
```

**Кто что видит:**
| Участник | Информация |
|----------|------------|
| **ISP** | VPN трафик к Windscribe |
| **Windscribe** | Соединение к Tor entry node |
| **Tor exit node** | ⚡ Шифрованный V2Ray трафик к proxy.example.com:443 |
| **Прокси сервер** | Твои запросы, но от Tor exit IP |

✅ Tor exit нода **НЕ МОЖЕТ** прослушивать трафик — видит только шифрованный V2Ray!  
✅ Прокси не знает твой реальный IP  
✅ Windscribe не знает что ты делаешь  
⚠️ Медленнее (~15-30 Mbps)

---

### 📊 Сравнение режимов:

| Режим | Цепочка | Скорость | Анонимность | Tor exit видит? |
|--------|---------|----------|-------------|------------------|
| 🟢 Fast | VPN → Proxy | ⚡⚡⚡⚡ | ⭐⭐⭐ | — нет Tor |
| 🟣 Paranoid (no V2Ray hop after Tor yet) | VPN → Tor → Proxy | ⚡⚡ | ⭐⭐⭐⭐⭐ | ❌ Только шифр. V2Ray |

> 🔑 **Ключевое преимущество**: V2Ray/Proxy в конце цепочки шифрует трафик от потенциально злонамеренных Tor exit нод!

## 🛡️ Компоненты системы

### 1. OpenVPN (VPN клиент)
- **Роль**: Первый слой защиты, скрывает ваш реальный IP
- **Провайдер**: Windscribe (или любой другой)
- **Протокол**: UDP/TCP
- **Порт**: 443, 1194
- **Шифрование**: AES-256-GCM
- **Файлы**:
  - `/etc/openvpn/client/windscribe.conf`
  - `/etc/openvpn/auth/windscribe-auth.txt`

### 2. V2Ray/XRay (Прокси)
- **Роль**: Дополнительный слой обфускации, обход DPI
- **UI**: v2rayA (веб-интерфейс на :2017)
- **Режим**: Transparent proxy (tproxy)
- **Порт**: 12345 (внутренний)
- **Протоколы**: VLESS, VMess, Shadowsocks, Trojan, SOCKS
- **Фичи**:
  - Импорт подписок
  - Создание цепочек прокси
  - Маршрутизация трафика
  - WebSocket, gRPC транспорты

### 3. Tor (Опциональный)

> ⚠️ **What Paranoid mode really does.** Client TCP and DNS go through Tor, and Tor itself goes out through the VPN tunnel (lab checks T1, T3 and T4 in `docs/LAB.md`). Other client traffic (UDP, ICMP) is dropped. The V2Ray hop **after** Tor described in this section is **not implemented**: the Tor exit node sees the traffic like any other Tor exit does. See `docs/ROADMAP.md`.
- **Роль**: Максимальная анонимность через луковичную маршрутизацию
- **SOCKS порт**: 9050
- **DNS порт**: 5353
- **Узлы**: 3 (entry, middle, exit)
- **Скорость**: Медленно (~5-30 Mbps)
- **Когда использовать**: Для критичных задач, deepweb

### 4. WiFi Hotspot (hostapd + dnsmasq)
- **hostapd**: WiFi Access Point
- **dnsmasq**: DHCP + DNS сервер
- **SSID**: ShadowPi (настраиваемо)
- **Шифрование**: WPA2-PSK
- **IP Range**: 10.0.0.10 - 10.0.0.250
- **Gateway**: 10.0.0.1 (сам Pi)

### 5. Firewall (nftables)
- **Роль**: Killswitch, защита от утечек
- **Правила**:
  - Блокировать весь трафик кроме VPN
  - NAT для клиентов через VPN
  - Redirect в V2Ray transparent proxy
  - Блокировать IPv6 (защита от утечек)
  - Разрешать только локальные DNS

### 6. Веб-панель управления
- **Nginx**: Веб-сервер
- **PHP**: Backend API
- **Порт**: 8080
- **Логин**: admin / [ваш_пароль]
- **Фичи**:
  - Статус всех сервисов
  - Проверка IP
  - Управление (старт/стоп)
  - Мониторинг системы (CPU, RAM, Temp)
  - Логи в реальном времени

## 📊 Использование ресурсов

### Raspberry Pi 4 (4GB RAM)

| Компонент | CPU | RAM | Примечание |
|-----------|-----|-----|------------|
| OpenVPN | 10-30% | ~50MB | Зависит от трафика |
| V2Ray | 5-15% | ~100MB | Легкий |
| Tor | 5-10% | ~50MB | Только если включен |
| hostapd | 1-5% | ~20MB | Минимальный |
| dnsmasq | <1% | ~10MB | Минимальный |
| Nginx+PHP | <1% | ~30MB | Минимальный |
| **Итого** | **20-50%** | **~300MB** | Остается много для системы |

**Idle (без нагрузки):**
- CPU: ~5-10%
- RAM: ~400MB / 4GB
- Temp: 40-50°C

**Под нагрузкой (активный трафик):**
- CPU: 30-60%
- RAM: ~600MB / 4GB
- Temp: 60-70°C (нужен радиатор!)

## 🌐 Сетевые интерфейсы

### На Raspberry Pi

| Интерфейс | Тип | IP | Назначение |
|-----------|-----|-------|------------|
| `eth0` | Ethernet | DHCP | WAN (интернет от провайдера) |
| `wlan0` | WiFi | 10.0.0.1/24 | LAN (WiFi Hotspot для клиентов) |
| `tun0` | Virtual | 10.x.x.x | VPN туннель (OpenVPN) |
| `wwan0` | USB Modem | DHCP | WAN (4G/LTE, опционально) |
| `lo` | Loopback | 127.0.0.1 | Локальный |

## 🔒 Безопасность

### ✅ Что защищено (режим Paranoid: VPN → Tor → V2Ray)

> ⚠️ **What Paranoid mode really does.** Client TCP and DNS go through Tor, and Tor itself goes out through the VPN tunnel (lab checks T1, T3 and T4 in `docs/LAB.md`). Other client traffic (UDP, ICMP) is dropped. The V2Ray hop **after** Tor described in this section is **not implemented**: the Tor exit node sees the traffic like any other Tor exit does. See `docs/ROADMAP.md`.

| Угроза | Защита | Как работает |
|--------|--------|--------------|
| **ISP видит трафик** | ✅ Защищено | VPN шифрует всё, ISP видит только VPN сервер |
| **VPN провайдер следит** | ✅ Защищено | VPN видит только Tor entry, не знает что делаешь |
| **Tor exit прослушивает** | ✅ Защищено | V2Ray шифрует трафик, exit видит только шифр |
| **Прокси логирует** | ⚠️ Частично | Прокси видит запросы, но от Tor exit IP |
| **IP адрес** | ✅ Защищено | Виден IP прокси сервера |
| **DNS утечки** | ✅ Защищено | DNS через VPN/Tor, не через ISP |
| **IPv6 утечки** | ✅ Защищено | IPv6 полностью отключен |
| **Killswitch** | ✅ Защищено | Блокирует трафик при падении VPN |

### 🛡️ Уровень защиты по режимам

> ⚠️ **What Paranoid mode really does.** Client TCP and DNS go through Tor, and Tor itself goes out through the VPN tunnel (lab checks T1, T3 and T4 in `docs/LAB.md`). Other client traffic (UDP, ICMP) is dropped. The V2Ray hop **after** Tor described in this section is **not implemented**: the Tor exit node sees the traffic like any other Tor exit does. See `docs/ROADMAP.md`.

| Угроза | 🟢 Fast | 🟣 Paranoid |
|--------|---------|-------------|
| ISP | ✅ | ✅ |
| Хакеры в кафе | ✅ | ✅ |
| VPN провайдер | ⚠️ Видит прокси | ✅ Видит только Tor |
| Tor exit node | — | ✅ V2Ray шифрует |
| Таргетированная слежка | ⚠️ | ✅ Очень сложно* |
| Государственные органы | ⚠️ | ✅ Очень сложно* |

> 🔐 *В режиме **Paranoid** даже при полном контроле одного звена (VPN, Tor, или прокси) — атакующий не получает полную картину:
> - VPN видит: Tor entry node
> - Tor видит: только шифрованный V2Ray трафик
> - Прокси видит: запросы от случайного Tor exit IP

### ⚠️ Что остаётся уязвимым (теоретически)

| Угроза | Описание | Как защититься |
|--------|----------|----------------|
| **Timing attacks** | Корреляция времени входа/выхода трафика | Редко, требует контроля всех узлов |
| **Browser fingerprinting** | Уникальные характеристики браузера | Используйте Tor Browser |
| **WebRTC leak** | Браузер может раскрыть IP | Отключите WebRTC в браузере |
| **Cookies/Sessions** | Авторизация раскрывает личность | Не логиньтесь в личные аккаунты |
| **Human error** | Логин в Gmail через Tor | Не смешивайте анонимную и личную активность |
| **Compromised device** | Вирус на устройстве | Держите ОС обновлённой |

### 🏛️ Против государственных атак

> ⚠️ **What Paranoid mode really does.** Client TCP and DNS go through Tor, and Tor itself goes out through the VPN tunnel (lab checks T1, T3 and T4 in `docs/LAB.md`). Other client traffic (UDP, ICMP) is dropped. The V2Ray hop **after** Tor described in this section is **not implemented**: the Tor exit node sees the traffic like any other Tor exit does. See `docs/ROADMAP.md`.

**В режиме Paranoid (VPN → Tor → V2Ray):**

✅ **Защищено от:**
- Массовой слежки (PRISM и подобные)
- Запросов к одному провайдеру
- Анализа трафика на уровне ISP
- Прослушки отдельных узлов

⚠️ **Теоретически уязвимо (требует огромных ресурсов):**
- Глобальная корреляция трафика (нужен контроль входа И выхода одновременно)
- Атаки на конечное устройство (0-day эксплойты)
- Социальная инженерия

> 💡 **Вывод**: Для 99.9% сценариев режим Paranoid обеспечивает достаточную защиту.
> Для работы уровня Сноудена дополнительно нужны: Tails OS, air-gapped компьютер, и паранойя 😄

## 🎯 Применения

### ✅ Подходит для:

1. **Обход блокировок** - обход цензуры, заблокированных сайтов
2. **Защита приватности** - скрыть активность от провайдера
3. **Публичные WiFi** - безопасность в кафе, аэропортах
4. **Pentest** - тестирование безопасности (легально!)
5. **Торренты** - анонимная загрузка (НЕ для пиратства!)
6. **Журналистика** - защита источников
7. **Активизм** - обход цензуры в авторитарных странах

### ❌ НЕ подходит для:

1. **Незаконная деятельность** - вы будете найдены
2. **100% анонимность** - против государств нужен Tor + Tails
3. **Высокоскоростной гейминг** - задержки будут высокие
4. **4K стриминг** - может тормозить
5. **Массовая торговля данными** - слишком медленно

## 📈 Производительность

### Скорость интернета

**С прямым подключением (без роутера):**
```
Download: 300 Mbps
Upload: 300 Mbps
Ping: 10 ms
```

**Через роутер (OpenVPN + V2Ray):**
```
Download: 60-120 Mbps  (↓60-80%)
Upload: 40-80 Mbps     (↓70-85%)
Ping: 50-100 ms        (↑500-900%)
```

**С Tor:**
```
Download: 10-30 Mbps   (↓90-95%)
Upload: 5-20 Mbps      (↓93-98%)
Ping: 200-500 ms       (↑2000-5000%)
```

### Рекомендации для оптимизации:

1. **Используйте WireGuard** вместо OpenVPN (+100% скорость)
2. **Выбирайте ближайший сервер** VPN/прокси
3. **UDP вместо TCP** для VPN (+20-50% скорость)
4. **Отключайте Tor** когда не нужна максимальная анонимность
5. **Охлаждение Pi** - радиатор или вентилятор
6. **Ethernet вместо WiFi** для WAN (стабильнее)

## 🔧 Обслуживание

### Регулярные проверки

**Ежедневно:**
```bash
curl ipinfo.io  # Проверка IP
```

**Еженедельно:**
```bash
sudo /opt/shadowpi/scripts/test-all.sh  # Тесты безопасности
```

**Ежемесячно:**
```bash
sudo apt update && sudo apt upgrade -y  # Обновления
sudo reboot  # Перезагрузка
```

### Логи

```bash
# Смотреть логи
sudo journalctl -u openvpn-windscribe -f
sudo journalctl -u v2raya -f
sudo tail -f /var/log/shadowpi/*.log
```

## 🚀 Будущие улучшения

Возможные дополнения:

- [ ] WireGuard поддержка (быстрее OpenVPN)
- [ ] Множественные VPN провайдеры
- [ ] Load balancing между прокси
- [ ] Fail-over (автопереключение при падении)
- [ ] Telegram бот для управления
- [ ] Mobile app
- [ ] DNS over HTTPS (DoH)
- [ ] Pi-hole интеграция (блокировка рекламы)
- [ ] IDS/IPS (Intrusion Detection)
- [ ] VPN on-demand (включать только для определенных сайтов)

---

**Проект создан с ❤️ для свободного интернета!**

