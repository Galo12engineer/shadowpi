#!/bin/bash
# Lab-only stand-in for v2rayA (its apt repo fails, check I1): the Xray core the installer
# DID install, with the transparent dokodemo-door inbound from docs/04 on :12345.
# The outbound is "freedom" instead of a real VLESS server, so traffic leaves through the VPN.
# The access log proves which connections went through the proxy.
set -euo pipefail
mkdir -p /var/log/xray && touch /var/log/xray/access.log && chown -R "$(systemctl show xray -p User --value)": /var/log/xray
cat > /usr/local/etc/xray/config.json <<'J'
{
  "log": { "access": "/var/log/xray/access.log", "loglevel": "warning" },
  "inbounds": [ { "tag": "transparent", "listen": "0.0.0.0", "port": 12345,
                  "protocol": "dokodemo-door",
                  "settings": { "network": "tcp", "followRedirect": true } } ],
  "outbounds": [ { "protocol": "freedom" } ]
}
J
systemctl restart xray; sleep 2
ss -ltn | grep ':12345 '
