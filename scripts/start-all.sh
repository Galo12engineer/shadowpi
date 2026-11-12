#!/bin/bash
# Start all ShadowPi services.
# Exit code: 0 only if every required service is running afterwards, 1 otherwise.
# The web panel reports this exit code, so do not hide failures here.

failed=()

# is_installed <unit>: optional components (v2rayA, Tor) may be absent.
is_installed() { systemctl cat "$1" >/dev/null 2>&1; }

# start_required <label> <unit>: start, then check that it really stayed up.
start_required() {
    echo "▶️  Запуск $1..."
    if ! sudo systemctl start "$2"; then
        echo "❌ $1: не удалось запустить ($2)" >&2
        failed+=("$1")
        return 1
    fi
}

echo "🚀 Запуск всех сервисов..."

# 0. Kill switch first (required): never open the hotspot without it. Normally the
#    shadowpi-killswitch unit has applied it at boot; if the rules are gone, apply them now.
if ! sudo iptables -S FORWARD 2>/dev/null | grep -q -- '-P FORWARD DROP'; then
    echo "▶️  Kill switch не активен — включаю..."
    if ! sudo /opt/shadowpi/scripts/killswitch.sh >/dev/null; then
        echo "❌ Kill switch: не удалось применить правила" >&2
        failed+=("Kill switch")
    fi
fi

# 1. OpenVPN (required: without it clients have no internet behind the kill switch)
start_required "OpenVPN" openvpn-windscribe
sleep 3

# 2. v2rayA (optional component)
if is_installed v2raya; then
    start_required "v2rayA" v2raya
    sleep 2
else
    echo "ℹ️  v2rayA не установлен — пропуск (трафик клиентов идёт только через VPN)"
fi

# 3. V2Ray redirect. Not applied when no proxy is listening; that is a supported state
#    (clients stay on the VPN), so it is a warning, not a failure.
echo "▶️  Настройка iptables для V2Ray..."
/opt/shadowpi/scripts/setup-v2ray-redirect.sh || echo "⚠️  V2Ray redirect не включён — трафик клиентов идёт только через VPN"

# 3b. Tor, only if Paranoid mode is on: its redirect is in place, so without Tor the
#     clients would have no internet.
if [ -e /opt/shadowpi/status/tor-mode ]; then
    start_required "Tor (режим Paranoid)" tor
fi

# 4. WiFi Hotspot (required)
start_required "WiFi Hotspot (hostapd)" hostapd
start_required "DHCP/DNS (dnsmasq)" dnsmasq
sleep 2

# 5. A unit can start and die a moment later, so check the final state too.
echo ""
echo "📊 Статус сервисов:"
for pair in "OpenVPN:openvpn-windscribe" "WiFi Hotspot (hostapd):hostapd" "DHCP/DNS (dnsmasq):dnsmasq"; do
    label="${pair%%:*}"; unit="${pair##*:}"
    state=$(systemctl is-active "$unit" 2>/dev/null)
    echo "$label: $state"
    if [ "$state" != "active" ] && [[ ! " ${failed[*]} " == *" $label "* ]]; then
        failed+=("$label")
    fi
done
is_installed v2raya && echo "v2rayA: $(systemctl is-active v2raya 2>/dev/null)"

echo ""
if [ ${#failed[@]} -gt 0 ]; then
    echo "❌ Не запущено: $(IFS=,; echo "${failed[*]}")" >&2
    exit 1
fi
echo "✅ Все сервисы запущены!"
echo "🔒 Проверьте ваш IP: curl ipinfo.io"
