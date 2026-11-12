#!/bin/bash
# Tor transparent proxy for Wi-Fi clients ("Paranoid" mode).
#
#   setup-tor-redirect.sh          apply (only if Tor is listening on the hotspot address)
#   setup-tor-redirect.sh --force  apply even if Tor is not listening yet (boot, kill switch
#                                  re-run): clients then have no internet until Tor is up,
#                                  instead of silently going around Tor
#   setup-tor-redirect.sh off      remove
#
# While it is on, a client can reach the internet in exactly one way:
#   TCP          -> Tor TransPort (Tor then goes out through the VPN tunnel)
#   DNS (udp/53) -> Tor DNSPort
#   anything else a client sends towards the internet (other UDP, ICMP) is dropped,
#   because Tor cannot carry it and letting it out through the VPN would bypass Tor.
# Connections to the router itself (panel, SSH) stay direct.
# Safe to run repeatedly: old rules are removed before new ones are added.
set -euo pipefail

LAN_IF="${LAN_IF:-wlan0}"
TRANS_PORT="${TOR_TRANS_PORT:-9040}"
DNS_PORT="${TOR_DNS_PORT:-5353}"
CHAIN=SHADOWPI_TOR
STATE=/opt/shadowpi/status/tor-mode   # exists = Paranoid mode is on (read by the panel and killswitch.sh)

remove_rules() {
    while iptables -t nat -D PREROUTING -i "$LAN_IF" -j "$CHAIN" 2>/dev/null; do :; done
    iptables -t nat -F "$CHAIN" 2>/dev/null || true
    iptables -t nat -X "$CHAIN" 2>/dev/null || true
    while iptables -D INPUT -i "$LAN_IF" -p tcp --dport "$TRANS_PORT" -j ACCEPT 2>/dev/null; do :; done
    while iptables -D INPUT -i "$LAN_IF" -p udp --dport "$DNS_PORT" -j ACCEPT 2>/dev/null; do :; done
    while iptables -D INPUT -i "$LAN_IF" -p tcp --dport 53 -j REJECT --reject-with tcp-reset 2>/dev/null; do :; done
    while iptables -D FORWARD -i "$LAN_IF" -j DROP 2>/dev/null; do :; done
}

if [ "${1:-}" = "off" ]; then
    remove_rules
    rm -f "$STATE"
    echo "Tor redirect removed"
    exit 0
fi

# REDIRECT delivers to the address of $LAN_IF, so Tor bound only to 127.0.0.1 does not count.
if [ "${1:-}" != "--force" ] && ! ss -ltnH "sport = :$TRANS_PORT" | awk '{print $4}' | grep -qv '^127\.'; then
    echo "ERROR: Tor is not listening on :$TRANS_PORT (outside 127.0.0.1)." >&2
    echo "       Redirect NOT applied. Use toggle-tor.sh paranoid, which configures and starts Tor." >&2
    exit 1
fi

remove_rules
iptables -t nat -N "$CHAIN"

# DNS first: clients ask the router (10.0.0.1:53) or any other resolver; both go to Tor.
iptables -t nat -A "$CHAIN" -p udp --dport 53 -j REDIRECT --to-ports "$DNS_PORT"
# The router's own services (panel, SSH) stay direct.
iptables -t nat -A "$CHAIN" -m addrtype --dst-type LOCAL -j RETURN
# All other client TCP goes into Tor.
iptables -t nat -A "$CHAIN" -p tcp -j REDIRECT --to-ports "$TRANS_PORT"

# Inserted first, so it wins over the V2Ray redirect when both are on.
iptables -t nat -I PREROUTING 1 -i "$LAN_IF" -j "$CHAIN"

# killswitch.sh sets INPUT policy DROP; let the redirected connections reach Tor.
iptables -I INPUT -i "$LAN_IF" -p tcp --dport "$TRANS_PORT" -j ACCEPT
iptables -I INPUT -i "$LAN_IF" -p udp --dport "$DNS_PORT" -j ACCEPT
# DNS over TCP would be answered by dnsmasq through the VPN, not through Tor: refuse it.
iptables -I INPUT -i "$LAN_IF" -p tcp --dport 53 -j REJECT --reject-with tcp-reset
# Nothing from a client is forwarded any more (TCP and DNS are delivered locally to Tor).
iptables -I FORWARD 1 -i "$LAN_IF" -j DROP

mkdir -p "$(dirname "$STATE")"
date > "$STATE"
echo "Tor redirect applied: $LAN_IF tcp -> :$TRANS_PORT, dns -> :$DNS_PORT, other client traffic dropped"
