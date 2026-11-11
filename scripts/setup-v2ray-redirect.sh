#!/bin/bash
# V2Ray/Xray transparent proxy: send Wi-Fi clients' TCP to the local transparent inbound.
#
#   setup-v2ray-redirect.sh        apply (only if the proxy is listening)
#   setup-v2ray-redirect.sh off    remove
#
# Safe to run repeatedly: old rules are removed before new ones are added.
set -euo pipefail

PORT="${V2RAY_REDIRECT_PORT:-12345}"   # dokodemo-door inbound, see docs/04_V2RAY_SETUP.md
LAN_IF="${LAN_IF:-wlan0}"

remove_rules() {
    while iptables -t nat -D PREROUTING -i "$LAN_IF" -p tcp -j V2RAY 2>/dev/null; do :; done
    while iptables -D INPUT -i "$LAN_IF" -p tcp --dport "$PORT" -j ACCEPT 2>/dev/null; do :; done
    iptables -t nat -F V2RAY 2>/dev/null || true
    iptables -t nat -X V2RAY 2>/dev/null || true
}

if [ "${1:-}" = "off" ]; then
    remove_rules
    echo "V2Ray redirect removed"
    exit 0
fi

# Never redirect into a port nobody listens on: every client TCP connection would die.
# REDIRECT delivers to the address of $LAN_IF, so a proxy bound only to 127.0.0.1 does not count.
if ! ss -ltnH "sport = :$PORT" | awk '{print $4}' | grep -qv '^127\.'; then
    remove_rules
    echo "ERROR: no V2Ray/Xray transparent inbound is listening on :$PORT (outside 127.0.0.1)." >&2
    echo "       Redirect NOT applied: clients go through the VPN only." >&2
    exit 1
fi

remove_rules
iptables -t nat -N V2RAY

# Connections to the router itself (panel, DNS, SSH, v2rayA UI) stay direct.
# Skipping by destination ADDRESS, not by port: skipping ports 80/443 would send
# almost all web traffic around the proxy.
iptables -t nat -A V2RAY -m addrtype --dst-type LOCAL -j RETURN
for net in 0.0.0.0/8 10.0.0.0/8 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12 \
           192.168.0.0/16 224.0.0.0/4 240.0.0.0/4; do
    iptables -t nat -A V2RAY -d "$net" -j RETURN
done
iptables -t nat -A V2RAY -p tcp -j REDIRECT --to-ports "$PORT"
iptables -t nat -A PREROUTING -i "$LAN_IF" -p tcp -j V2RAY

# killswitch.sh sets INPUT policy DROP; let redirected client connections reach the proxy.
iptables -I INPUT -i "$LAN_IF" -p tcp --dport "$PORT" -j ACCEPT

echo "V2Ray redirect applied: $LAN_IF tcp -> :$PORT"
