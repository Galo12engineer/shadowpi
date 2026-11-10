#!/bin/bash
# Test OpenVPN server standing in for Windscribe. Pushes redirect-gateway like a real provider.
set -euo pipefail
export EASYRSA_BATCH=1 EASYRSA_PKI=/pki/pki
if [ ! -f /pki/client.ovpn ]; then
  cd /pki && /usr/share/easy-rsa/easyrsa init-pki
  /usr/share/easy-rsa/easyrsa build-ca nopass
  /usr/share/easy-rsa/easyrsa build-server-full server nopass
  /usr/share/easy-rsa/easyrsa build-client-full client nopass
  P=/pki/pki
  { echo "client"; echo "dev tun"; echo "proto udp"; echo "remote 172.30.0.20 1194"
    echo "resolv-retry infinite"; echo "remote-cert-tls server"; echo "persist-key"; echo "persist-tun"
    echo "<ca>"; cat $P/ca.crt; echo "</ca>"
    echo "<cert>"; sed -n '/BEGIN/,/END/p' $P/issued/client.crt; echo "</cert>"
    echo "<key>"; cat $P/private/client.key; echo "</key>"; } > /pki/client.ovpn
  chmod 644 /pki/client.ovpn
fi
ip route add 198.51.100.0/24 via 172.30.0.30
iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o eth0 -j MASQUERADE
P=/pki/pki
exec openvpn --dev tun --proto udp --port 1194 --server 10.8.0.0 255.255.255.0 --topology subnet \
  --ca $P/ca.crt --cert $P/issued/server.crt --key $P/private/server.key --dh none \
  --push "redirect-gateway def1" --keepalive 10 60 --verb 3
