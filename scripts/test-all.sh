#!/bin/bash
# Comprehensive security and functionality tests

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  🧪 ShadowPi Security Tests"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() {
    echo -e "${GREEN}✅ PASS:${NC} $1"
}

fail() {
    echo -e "${RED}❌ FAIL:${NC} $1"
}

warn() {
    echo -e "${YELLOW}⚠️  WARN:${NC} $1"
}

info() {
    echo -e "ℹ️  $1"
}

# Test 1: Check Public IP
echo "━━━ Test 1: Public IP Check ━━━"
PUBLIC_IP=$(curl -s ipinfo.io/ip)
info "Public IP: $PUBLIC_IP"

IP_INFO=$(curl -s ipinfo.io/json)
COUNTRY=$(echo $IP_INFO | jq -r '.country')
CITY=$(echo $IP_INFO | jq -r '.city')
ORG=$(echo $IP_INFO | jq -r '.org')

info "Location: $CITY, $COUNTRY"
info "Provider: $ORG"

# Check if IP is different from local ISP (basic check)
if [[ "$ORG" == *"Windscribe"* ]] || [[ "$ORG" == *"VPN"* ]]; then
    pass "IP is from VPN provider"
else
    warn "IP might be your real IP!"
fi

echo ""

# Test 2: DNS Leak Test
echo "━━━ Test 2: DNS Leak Test ━━━"
DNS_SERVERS=$(dig +short whoami.akamai.net @resolver1.opendns.com)
info "DNS resolves to: $DNS_SERVERS"

if [[ "$DNS_SERVERS" == "$PUBLIC_IP" ]]; then
    pass "DNS matches VPN IP"
else
    fail "DNS leak detected! DNS: $DNS_SERVERS, IP: $PUBLIC_IP"
fi

echo ""

# Test 3: IPv6 Leak Test
echo "━━━ Test 3: IPv6 Leak Test ━━━"
IPV6=$(curl -s -6 ifconfig.co 2>/dev/null)

if [ -z "$IPV6" ]; then
    pass "IPv6 is disabled (no leaks)"
else
    fail "IPv6 is enabled! Leak detected: $IPV6"
fi

echo ""

# Test 4: WebRTC Leak Test
echo "━━━ Test 4: WebRTC Leak Test ━━━"
info "WebRTC leaks can only be tested in browser"
info "Visit: https://browserleaks.com/webrtc"
warn "Ensure WebRTC is disabled in browser or use extension"

echo ""

# Test 5: Service Status
echo "━━━ Test 5: Service Status ━━━"

services=("openvpn-windscribe" "v2raya" "hostapd" "dnsmasq")

for service in "${services[@]}"; do
    if systemctl is-active --quiet $service; then
        pass "$service is running"
    else
        fail "$service is NOT running"
    fi
done

echo ""

# Test 6: VPN Connection Test
echo "━━━ Test 6: VPN Connection ━━━"

if ip addr show tun0 &>/dev/null; then
    pass "tun0 interface exists"
    VPN_IP=$(ip addr show tun0 | grep "inet " | awk '{print $2}')
    info "VPN IP: $VPN_IP"
else
    fail "tun0 interface not found"
fi

echo ""

# Test 7: WiFi Hotspot Test
echo "━━━ Test 7: WiFi Hotspot ━━━"

if iw dev wlan0 info &>/dev/null; then
    pass "wlan0 is in AP mode"
    SSID=$(grep "^ssid=" /etc/hostapd/hostapd.conf | cut -d'=' -f2)
    info "SSID: $SSID"
    
    CLIENTS=$(iw dev wlan0 station dump 2>/dev/null | grep -c "^Station" || echo "0")
    info "Connected clients: $CLIENTS"
else
    fail "wlan0 is not in AP mode"
fi

echo ""

# Test 8: Speed Test
echo "━━━ Test 8: Speed Test ━━━"
info "Running speedtest (this may take 30 seconds)..."

if command -v speedtest-cli &> /dev/null; then
    SPEED_RESULT=$(speedtest-cli --simple 2>/dev/null)
    
    if [ $? -eq 0 ]; then
        echo "$SPEED_RESULT"
        
        DOWNLOAD=$(echo "$SPEED_RESULT" | grep "Download:" | awk '{print $2}')
        UPLOAD=$(echo "$SPEED_RESULT" | grep "Upload:" | awk '{print $2}')
        
        if (( $(echo "$DOWNLOAD > 10" | bc -l) )); then
            pass "Download speed OK: ${DOWNLOAD} Mbit/s"
        else
            warn "Download speed slow: ${DOWNLOAD} Mbit/s"
        fi
    else
        fail "Speedtest failed"
    fi
else
    warn "speedtest-cli not installed"
fi

echo ""

# Test 9: Firewall Rules
echo "━━━ Test 9: Firewall Check ━━━"

if sudo iptables -t nat -L V2RAY -n &>/dev/null; then
    pass "V2Ray iptables rules exist"
else
    fail "V2Ray iptables rules not found"
fi

echo ""

# Test 10: Port Scan (External)
echo "━━━ Test 10: External Port Scan ━━━"
info "Checking common ports from outside..."

OPEN_PORTS=$(curl -s "https://api.hackertarget.com/nmap/?q=$PUBLIC_IP" | grep "open" || echo "none")

if [[ "$OPEN_PORTS" == "none" ]] || [[ -z "$OPEN_PORTS" ]]; then
    pass "No obvious open ports detected"
else
    warn "Some ports might be open:"
    echo "$OPEN_PORTS"
fi

echo ""

# Final Summary
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  📊 Test Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Current IP: $PUBLIC_IP"
echo "Location: $CITY, $COUNTRY"
echo "Provider: $ORG"
echo ""
echo "For comprehensive leak tests, visit:"
echo "  • https://ipleak.net"
echo "  • https://browserleaks.com"
echo "  • https://dnsleaktest.com"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
