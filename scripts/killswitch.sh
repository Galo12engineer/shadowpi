#!/bin/bash
# Kill switch (iptables): Wi-Fi clients and the router itself reach the internet only
# through the VPN tunnel. If the VPN is down, nothing leaves.
#
# The rules do not list WAN interfaces. Traffic is allowed on three interfaces only
# (loopback, the hotspot, the tunnel) plus the VPN handshake; everything else is dropped,
# whatever the WAN is called: eth0, wwan0, usb0, usb1, eth1, enx* (see wan-switch.sh).
#
# The VPN handshake is allowed only to the server(s) in the OpenVPN config: the address,
# port and protocol of each 'remote' line. Not "any host on port 443": that would let the
# router itself talk to the whole internet with its real IP while the VPN is down.
# Trade-offs and the hostname case are explained in docs/08_FIREWALL.md.
#
# Exit code: 0 = applied; 2 = applied, but a 'remote' hostname could not be resolved, so
# the VPN cannot connect until this script is run again (the firewall stays closed).

set -e

LAN_IF="${LAN_IF:-wlan0}"   # Wi-Fi hotspot
VPN_IF="${VPN_IF:-tun0}"    # OpenVPN tunnel
VPN_CONF="${VPN_CONF:-/etc/openvpn/client/windscribe.conf}"
ENDPOINT_CACHE="${ENDPOINT_CACHE:-/opt/shadowpi/status/vpn-endpoints}"   # lines: "host ip"
HOSTS_TAG="# shadowpi-killswitch: pinned VPN server"

# ═══ VPN server endpoints (worked out BEFORE the rules are replaced) ═══

# Prints "host port proto" for every 'remote' line of the OpenVPN config.
vpn_remotes() {
    [ -r "$VPN_CONF" ] || return 0
    awk '
        { sub(/[#;].*/, "") }
        $1 == "proto"                  { proto = $2 }
        $1 == "port" || $1 == "rport"  { port = $2 }
        $1 == "remote"                 { n++; host[n] = $2; rport[n] = $3; rproto[n] = $4 }
        END {
            if (proto == "") proto = "udp"
            if (port == "")  port = "1194"
            for (i = 1; i <= n; i++) {
                pr = (rproto[i] != "" ? rproto[i] : proto)
                print host[i], (rport[i] != "" ? rport[i] : port), (pr ~ /^tcp/ ? "tcp" : "udp")
            }
        }' "$VPN_CONF"
}

is_ipv4() { [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; }

# Real DNS only ("-s dns"): the answer must not come from our own pinned /etc/hosts lines.
dns_lookup() { timeout 8 getent -s dns ahostsv4 "$1" 2>/dev/null | awk '{print $1}' | sort -u || true; }

cached_ips() { [ -r "$ENDPOINT_CACHE" ] && awk -v h="$1" '$1 == h {print $2}' "$ENDPOINT_CACHE" || true; }

# First setup only: no cached address and DNS already blocked by an earlier run of this
# script. Open DNS for this one lookup: to the configured resolvers only, for root's
# processes only (so dnsmasq cannot forward client queries through it), for a few seconds.
dns_lookup_pinhole() {
    local ns resolvers
    resolvers=$(awk '$1 == "nameserver" {print $2}' /etc/resolv.conf 2>/dev/null | grep -E '^[0-9.]+$' || true)
    for ns in $resolvers; do
        iptables -I OUTPUT -p udp -d "$ns" --dport 53 -m owner --uid-owner 0 -j ACCEPT 2>/dev/null || true
    done
    dns_lookup "$1"
    for ns in $resolvers; do
        iptables -D OUTPUT -p udp -d "$ns" --dport 53 -m owner --uid-owner 0 -j ACCEPT 2>/dev/null || true
    done
}

ENDPOINTS=()      # "ip port proto": what the handshake rules allow
PINNED_HOSTS=()   # "ip host": written to /etc/hosts so OpenVPN needs no DNS to reconnect
UNRESOLVED=()

while read -r host port proto; do
    [[ "$host" =~ ^[A-Za-z0-9.-]+$ && "$port" =~ ^[0-9]+$ ]] || continue
    if is_ipv4 "$host"; then
        ENDPOINTS+=("$host $port $proto")
        continue
    fi
    ips=$(dns_lookup "$host")                           # normal case: VPN up, DNS goes through it
    [ -n "$ips" ] || ips=$(cached_ips "$host")          # VPN down: addresses from the last run
    [ -n "$ips" ] || ips=$(dns_lookup_pinhole "$host")  # first setup
    if [ -z "$ips" ]; then
        UNRESOLVED+=("$host")
        continue
    fi
    for ip in $ips; do
        ENDPOINTS+=("$ip $port $proto")
        PINNED_HOSTS+=("$ip $host")
    done
done < <(vpn_remotes)

echo "🔒 Активация Killswitch..."

# Flush all existing rules
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X

# Default policies: DROP everything
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP

echo "  → Default policy: DROP"

# ═══ INPUT CHAIN ═══

# Loopback (localhost)
iptables -A INPUT -i lo -j ACCEPT

# Established/Related connections
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# ICMP (ping)
iptables -A INPUT -p icmp -j ACCEPT

# SSH from the hotspot and from the wired LAN
iptables -A INPUT -i "$LAN_IF" -p tcp --dport 22 -j ACCEPT
iptables -A INPUT -i eth0 -p tcp --dport 22 -j ACCEPT

# Web panel and v2rayA UI (hotspot only)
iptables -A INPUT -i "$LAN_IF" -p tcp --dport 80 -j ACCEPT
iptables -A INPUT -i "$LAN_IF" -p tcp --dport 8080 -j ACCEPT
iptables -A INPUT -i "$LAN_IF" -p tcp --dport 443 -j ACCEPT
iptables -A INPUT -i "$LAN_IF" -p tcp --dport 2017 -j ACCEPT  # v2rayA

# DNS from the hotspot (dnsmasq)
iptables -A INPUT -i "$LAN_IF" -p udp --dport 53 -j ACCEPT
iptables -A INPUT -i "$LAN_IF" -p tcp --dport 53 -j ACCEPT

# DHCP from the hotspot
iptables -A INPUT -i "$LAN_IF" -p udp --dport 67:68 -j ACCEPT

# VPN tunnel
iptables -A INPUT -i "$VPN_IF" -j ACCEPT

echo "  → INPUT rules applied"

# ═══ OUTPUT CHAIN (the router's own traffic) ═══

iptables -A OUTPUT -o lo -j ACCEPT
iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -o "$LAN_IF" -j ACCEPT
iptables -A OUTPUT -o "$VPN_IF" -j ACCEPT

# VPN handshake: the only thing allowed out through the WAN, on any WAN interface,
# and only to the VPN server's own address, port and protocol.
for endpoint in "${ENDPOINTS[@]}"; do
    read -r ip port proto <<< "$endpoint"
    iptables -A OUTPUT -p "$proto" -d "$ip" --dport "$port" -j ACCEPT
    echo "  → VPN server allowed: $ip:$port/$proto"
done

# KILL SWITCH: everything else is dropped, on every interface. The rule names no interface
# on purpose: a WAN that is not in some list (a 4G modem, a USB adapter) is still covered.
# The log line shows the router's own blocked packets only and is rate-limited.
iptables -A OUTPUT -m limit --limit 6/min --limit-burst 5 -j LOG --log-prefix "KILLSWITCH-OUT: " --log-level 4
iptables -A OUTPUT -j DROP

echo "  → OUTPUT rules applied (KILLSWITCH active)"

# ═══ FORWARD CHAIN (Wi-Fi clients) ═══

iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# The only path for clients: hotspot → tunnel, and the replies back.
iptables -A FORWARD -i "$LAN_IF" -o "$VPN_IF" -j ACCEPT
iptables -A FORWARD -i "$VPN_IF" -o "$LAN_IF" -j ACCEPT

# KILL SWITCH: clients never go out through any other interface.
# Not logged: a log line would record which address each client tried to reach.
iptables -A FORWARD -j DROP

echo "  → FORWARD rules applied (WiFi → VPN only)"

# ═══ NAT ═══

# Masquerade clients behind the tunnel address
iptables -t nat -A POSTROUTING -o "$VPN_IF" -j MASQUERADE

echo "  → NAT rules applied"

# ═══ IPv6 ═══

# Block IPv6 completely
ip6tables -P INPUT DROP
ip6tables -P FORWARD DROP
ip6tables -P OUTPUT DROP
ip6tables -F
ip6tables -A INPUT -i lo -j ACCEPT
ip6tables -A OUTPUT -o lo -j ACCEPT

echo "  → IPv6 blocked"

# ═══ Pinned VPN hostnames ═══

# With the VPN down the router has no DNS (that is the point), so OpenVPN could never look
# its server up again. The addresses allowed above are therefore also written to /etc/hosts.
# The file is rewritten in place (no rename): it can be a bind mount.
if [ ${#PINNED_HOSTS[@]} -gt 0 ] || grep -qF "$HOSTS_TAG" /etc/hosts 2>/dev/null; then
    hosts_keep=$(grep -vF "$HOSTS_TAG" /etc/hosts 2>/dev/null || true)
    {
        [ -z "$hosts_keep" ] || printf '%s\n' "$hosts_keep"
        for entry in "${PINNED_HOSTS[@]}"; do echo "$entry $HOSTS_TAG"; done
    } > /etc/hosts
fi
if [ ${#PINNED_HOSTS[@]} -gt 0 ]; then
    mkdir -p "$(dirname "$ENDPOINT_CACHE")"
    for entry in "${PINNED_HOSTS[@]}"; do read -r ip host <<< "$entry"; echo "$host $ip"; done > "$ENDPOINT_CACHE"
    echo "  → VPN hostnames pinned in /etc/hosts"
fi

# ═══ Paranoid (Tor) mode ═══

# This script has just flushed every rule, including the Tor redirect. If Paranoid mode is
# on, put it back, forced: without it the clients would silently go through the plain VPN.
# If Tor is not running (early boot), they have no internet until it is.
if [ -e /opt/shadowpi/status/tor-mode ] && [ -x /opt/shadowpi/scripts/setup-tor-redirect.sh ]; then
    /opt/shadowpi/scripts/setup-tor-redirect.sh --force
    echo "  → Paranoid mode: Tor redirect re-applied"
fi

# Save the rules
if command -v iptables-save &> /dev/null; then
    mkdir -p /etc/iptables
    iptables-save > /etc/iptables/rules.v4
    ip6tables-save > /etc/iptables/rules.v6
    echo "  → Rules saved to /etc/iptables/"
fi

echo ""
echo "✅ Killswitch активирован!"
echo ""
echo "Защита:"
echo "  • Весь трафик ТОЛЬКО через VPN ($VPN_IF)"
echo "  • Если VPN упадет - интернет заблокируется (на любом WAN-интерфейсе)"
echo "  • IPv6 полностью отключен"
echo "  • DNS только через VPN"
echo ""
echo "Для просмотра заблокированного трафика роутера:"
echo "  sudo dmesg | grep KILLSWITCH"
echo "  sudo journalctl -k | grep KILLSWITCH"

if [ ${#ENDPOINTS[@]} -eq 0 ] && [ ${#UNRESOLVED[@]} -eq 0 ]; then
    echo ""
    echo "⚠️  В $VPN_CONF нет строки 'remote': VPN-сервер не разрешён, интернета не будет." >&2
    echo "   Настройте VPN (docs/03_OPENVPN_SETUP.md) и запустите этот скрипт ещё раз." >&2
fi
if [ ${#UNRESOLVED[@]} -gt 0 ]; then
    echo "" >&2
    echo "❌ Не удалось узнать адрес VPN-сервера: ${UNRESOLVED[*]}" >&2
    echo "   Firewall закрыт, но VPN не сможет подключиться." >&2
    echo "   Укажите IP в строке 'remote' или запустите скрипт ещё раз, когда DNS доступен." >&2
    exit 2
fi
