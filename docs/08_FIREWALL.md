# 08. Firewall и Killswitch

## 🛡️ Зачем нужен Firewall?

Firewall защищает от:
- 🔒 **Утечек IP** - если VPN упадет, трафик не пойдет напрямую
- 🚫 **DNS утечек** - только VPN DNS разрешен
- 🔐 **IPv6 утечек** - блокирует весь IPv6
- ⚔️ **Атак снаружи** - блокирует входящие подключения
- 📊 **Нежелательного трафика** - фильтрация по портам/адресам

## 🔥 nftables vs iptables

Мы используем **nftables** (современная замена iptables):

| Фича | iptables | nftables |
|------|----------|----------|
| Скорость | Средняя | Быстрее |
| Синтаксис | Сложный | Проще |
| Производительность | Хорошая | Лучше |
| Будущее | Устаревает | Активно развивается |

## 📝 Базовая конфигурация nftables

### Полный конфиг с killswitch

```bash
sudo nano /etc/nftables.conf
```

```conf
#!/usr/sbin/nft -f
# ShadowPi Firewall with Killswitch

# Очистка старых правил
flush ruleset

# Основная таблица
table inet filter {
    
    # ═══ INPUT CHAIN ═══
    # Входящие соединения
    chain input {
        type filter hook input priority 0; policy drop;
        
        # Loopback (localhost) - разрешить все
        iif lo accept
        
        # Established/Related - разрешить ответы
        ct state established,related accept
        
        # Invalid пакеты - дроп
        ct state invalid drop
        
        # ICMP (ping) - разрешить
        ip protocol icmp accept
        ip6 nexthdr icmpv6 accept
        
        # SSH с локальной сети и WiFi
        iifname { "wlan0", "eth0" } tcp dport 22 accept
        
        # HTTP/HTTPS с WiFi (веб-панель)
        iifname "wlan0" tcp dport { 80, 8080, 443, 2017 } accept
        
        # DNS с WiFi
        iifname "wlan0" udp dport 53 accept
        iifname "wlan0" tcp dport 53 accept
        
        # DHCP с WiFi
        iifname "wlan0" udp dport 67 accept
        
        # Все остальное - дроп
        counter drop
    }
    
    # ═══ FORWARD CHAIN ═══
    # Трафик между интерфейсами (роутинг)
    chain forward {
        type filter hook forward priority 0; policy drop;
        
        # Established/Related
        ct state established,related accept
        
        # Invalid - дроп
        ct state invalid drop
        
        # WiFi → VPN (tun0) - разрешить
        iifname "wlan0" oifname "tun0" accept
        
        # VPN → WiFi - только established
        iifname "tun0" oifname "wlan0" ct state established,related accept
        
        # Блокировать WiFi → eth0/wwan0 (killswitch!)
        # Весь трафик ТОЛЬКО через tun0
        iifname "wlan0" oifname { "eth0", "wwan0" } counter drop
        
        # Логировать заблокированное
        iifname "wlan0" oifname != "tun0" log prefix "KILLSWITCH: " drop
    }
    
    # ═══ OUTPUT CHAIN ═══
    # Исходящие с самого роутера
    chain output {
        type filter hook output priority 0; policy drop;
        
        # Loopback
        oif lo accept
        
        # Established/Related
        ct state established,related accept
        
        # DNS (только через VPN!)
        oifname "tun0" udp dport 53 accept
        oifname "tun0" tcp dport 53 accept
        
        # VPN соединение через eth0/wwan0
        oifname { "eth0", "wwan0" } udp dport { 443, 1194, 1195 } accept
        oifname { "eth0", "wwan0" } tcp dport { 443, 1194, 1195 } accept
        
        # Весь остальной трафик через VPN
        oifname "tun0" accept
        
        # Локальные интерфейсы
        oifname "wlan0" accept
        
        # Блокировать прямой выход (killswitch)
        oifname { "eth0", "wwan0" } log prefix "KILLSWITCH-OUT: " drop
    }
}

# ═══ NAT ТАБЛИЦА ═══
table ip nat {
    
    # POSTROUTING (NAT для клиентов)
    chain postrouting {
        type nat hook postrouting priority 100; policy accept;
        
        # Masquerade для WiFi клиентов через VPN
        oifname "tun0" masquerade
        
        # Опционально: через eth0 если VPN отключен (НЕ рекомендуется!)
        # oifname "eth0" masquerade
    }
    
    # PREROUTING (Redirect для V2Ray)
    chain prerouting {
        type nat hook prerouting priority -100; policy accept;
        
        # Игнорировать локальные адреса
        ip daddr { 0.0.0.0/8, 10.0.0.0/8, 127.0.0.0/8, 169.254.0.0/16, \
                   172.16.0.0/12, 192.168.0.0/16, 224.0.0.0/4, 240.0.0.0/4 } return
        
        # Redirect TCP трафик с WiFi на V2Ray transparent proxy
        iifname "wlan0" tcp dport != { 22, 80, 8080, 2017 } redirect to :12345
    }
}

# ═══ IPv6 БЛОКИРОВКА ═══
table ip6 filter {
    chain input {
        type filter hook input priority 0; policy drop;
        # Только loopback
        iif lo accept
        # Все остальное - дроп (защита от IPv6 утечек)
        counter drop
    }
    
    chain forward {
        type filter hook forward priority 0; policy drop;
        counter drop
    }
    
    chain output {
        type filter hook output priority 0; policy drop;
        oif lo accept
        counter drop
    }
}
```

### Применение конфигурации

```bash
# Проверка синтаксиса
sudo nft -c -f /etc/nftables.conf

# Применить
sudo nft -f /etc/nftables.conf

# Сделать постоянным
sudo systemctl enable nftables
sudo systemctl start nftables

# Проверка правил
sudo nft list ruleset
```

## 🔴 Killswitch - что это?

**Killswitch** автоматически блокирует весь интернет трафик если VPN отключился.

**Без killswitch:**
```
VPN упал → Трафик идет напрямую → ВАШ РЕАЛЬНЫЙ IP ВИДЕН! ❌
```

**С killswitch:**
```
VPN упал → Firewall блокирует весь трафик → НЕТ УТЕЧЕК! ✅
```

### Тест killswitch

```bash
# 1. Проверьте IP (должен быть VPN)
curl ipinfo.io

# 2. Остановите VPN
sudo systemctl stop openvpn-windscribe

# 3. Попробуйте снова
curl ipinfo.io

# Должно быть:
# curl: (7) Failed to connect
# ИЛИ timeout

# ✅ Killswitch работает!

# 4. Восстановите VPN
sudo systemctl start openvpn-windscribe
```

## 📊 Мониторинг firewall

### Просмотр правил

```bash
# Все правила
sudo nft list ruleset

# Только filter таблица
sudo nft list table inet filter

# Только NAT
sudo nft list table ip nat

# С счетчиками пакетов
sudo nft list table inet filter -a
```

### Логи заблокированных пакетов

```bash
# В конфиге мы добавили:
# log prefix "KILLSWITCH: " drop

# Смотреть логи
sudo dmesg | grep KILLSWITCH
sudo journalctl -k | grep KILLSWITCH

# Real-time
sudo dmesg -w | grep KILLSWITCH
```

### Статистика

```bash
# Создайте скрипт мониторинга
sudo nano /opt/shadowpi/scripts/firewall-stats.sh
```

```bash
#!/bin/bash
# Firewall Statistics

echo "════════════════════════════════════"
echo "   Firewall Statistics"
echo "════════════════════════════════════"

# Счетчики по цепочкам
echo ""
echo "INPUT chain:"
sudo nft list chain inet filter input | grep counter

echo ""
echo "FORWARD chain:"
sudo nft list chain inet filter forward | grep counter

echo ""
echo "Заблокировано killswitch:"
sudo dmesg | grep "KILLSWITCH:" | wc -l

echo ""
echo "Последние 5 блокировок:"
sudo dmesg | grep "KILLSWITCH:" | tail -5
```

## 🔧 Дополнительные фичи

### Блокировка рекламы на уровне firewall

```bash
# Добавьте в nftables.conf

table inet filter {
    # ... существующие цепочки ...
    
    # Список рекламных доменов (IP адреса)
    set blocked_ips {
        type ipv4_addr
        flags interval
        elements = {
            142.250.185.142,  # Пример: ads.google.com
            157.240.1.35      # Пример: facebook ads
        }
    }
    
    chain forward {
        # ... существующие правила ...
        
        # Блокировать рекламные IP
        ip daddr @blocked_ips counter drop
    }
}
```

### Rate limiting (защита от DDoS)

```bash
# Ограничение новых соединений
chain input {
    # ... существующие правила ...
    
    # Максимум 10 новых SSH соединений в минуту
    tcp dport 22 ct state new limit rate 10/minute accept
    tcp dport 22 ct state new drop
}
```

### Port knocking (скрытый SSH)

```bash
# Открыть SSH только после "стука" в определенные порты
# (продвинутая фича, для параноидальной безопасности)
```

## 🔄 Альтернатива: iptables (legacy)

Если nftables не работает, используйте iptables:

```bash
sudo nano /opt/shadowpi/scripts/iptables-killswitch.sh
```

```bash
#!/bin/bash
# Killswitch using iptables

# Flush старых правил
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X

# Default policies
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP

# Loopback
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# Established/Related
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# WiFi клиенты
iptables -A INPUT -i wlan0 -j ACCEPT
iptables -A OUTPUT -o wlan0 -j ACCEPT

# VPN туннель
iptables -A INPUT -i tun0 -j ACCEPT
iptables -A OUTPUT -o tun0 -j ACCEPT

# VPN соединение (разрешить OpenVPN подключиться)
iptables -A OUTPUT -o eth0 -p udp --dport 443 -j ACCEPT
iptables -A OUTPUT -o eth0 -p udp --dport 1194 -j ACCEPT
iptables -A INPUT -i eth0 -p udp --sport 443 -j ACCEPT
iptables -A INPUT -i eth0 -p udp --sport 1194 -j ACCEPT

# NAT для WiFi клиентов
iptables -t nat -A POSTROUTING -o tun0 -j MASQUERADE

# FORWARD: WiFi → VPN
iptables -A FORWARD -i wlan0 -o tun0 -j ACCEPT
iptables -A FORWARD -i tun0 -o wlan0 -j ACCEPT

# V2Ray redirect
iptables -t nat -N V2RAY
iptables -t nat -A V2RAY -d 0.0.0.0/8 -j RETURN
iptables -t nat -A V2RAY -d 10.0.0.0/8 -j RETURN
iptables -t nat -A V2RAY -d 127.0.0.0/8 -j RETURN
iptables -t nat -A V2RAY -d 169.254.0.0/16 -j RETURN
iptables -t nat -A V2RAY -d 172.16.0.0/12 -j RETURN
iptables -t nat -A V2RAY -d 192.168.0.0/16 -j RETURN
iptables -t nat -A V2RAY -d 224.0.0.0/4 -j RETURN
iptables -t nat -A V2RAY -d 240.0.0.0/4 -j RETURN
iptables -t nat -A V2RAY -p tcp -j REDIRECT --to-ports 12345
iptables -t nat -A PREROUTING -i wlan0 -j V2RAY

# Сохранить правила
iptables-save > /etc/iptables/rules.v4

echo "✅ Killswitch applied (iptables)"
```

```bash
sudo chmod +x /opt/shadowpi/scripts/iptables-killswitch.sh
sudo /opt/shadowpi/scripts/iptables-killswitch.sh
```

## ✅ Готово!

Firewall с killswitch настроен! Переходите к **09_WEB_UI.md**
