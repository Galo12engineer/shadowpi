#!/bin/bash
# Stop all ShadowPi services.
# Exit code: 0 only if every service is stopped afterwards, 1 otherwise.

failed=()

echo "⏹️  Остановка всех сервисов..."

for unit in hostapd dnsmasq v2raya openvpn-windscribe tor; do
    # Optional components (v2rayA, Tor) may not be installed: nothing to stop.
    systemctl cat "$unit" >/dev/null 2>&1 || continue
    sudo systemctl stop "$unit" || true
    if [ "$(systemctl is-active "$unit" 2>/dev/null)" = "active" ]; then
        echo "❌ $unit всё ещё работает" >&2
        failed+=("$unit")
    fi
done

if [ ${#failed[@]} -gt 0 ]; then
    echo "❌ Не остановлено: $(IFS=,; echo "${failed[*]}")" >&2
    exit 1
fi
echo "✅ Все сервисы остановлены"
