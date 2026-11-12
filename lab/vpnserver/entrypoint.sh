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
# Docker Desktop hands packets from the real internet to this container with TCP checksums
# that were never filled in (they are marked "already verified"). Delivered locally that is
# harmless, but this server forwards them into the VPN tunnel, where the router's kernel
# checks them and drops every one (TcpInCsumErrors). Recompute checksums on the way in, so
# that TCP from the real internet works through the lab VPN. Needed for Tor (checks T1, T3).
tc qdisc add dev eth0 handle ffff: ingress
tc filter add dev eth0 parent ffff: protocol ip prio 1 u32 match u32 0 0 action csum ip4h and tcp and udp and icmp
P=/pki/pki
exec openvpn --dev tun --proto udp --port 1194 --server 10.8.0.0 255.255.255.0 --topology subnet \
  --ca $P/ca.crt --cert $P/issued/server.crt --key $P/private/server.key --dh none \
  --push "redirect-gateway def1" --keepalive 10 60 --verb 3
