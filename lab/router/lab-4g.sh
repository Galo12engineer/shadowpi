#!/bin/bash
# Lab-only: stand-ins for the 4G modem interfaces wan-switch.sh can use (usb0, eth1, enx*).
# A real modem needs hardware. A dummy interface takes every packet the kernel routes to it
# and counts it in tx_packets, so the counter shows whether the firewall let a packet out.
#
#   lab-4g.sh up <if>         create the interface; 203.0.113.0/24 ("the internet") is behind it
#   lab-4g.sh tx <if>         packets that left through it so far
#   lab-4g.sh control <if>    prove the counter works: send one packet that a temporary,
#                             single-destination ACCEPT rule lets out; prints how many left (1)
#   lab-4g.sh handshake <if>  route the VPN server through the interface and send one packet
#                             to the VPN port from windscribe.conf; prints how many left
#   lab-4g.sh down <if>       remove the interface
set -uo pipefail
ifc="$2"; NET=203.0.113; CONF=/etc/openvpn/client/windscribe.conf
tx() { cat "/sys/class/net/$ifc/statistics/tx_packets"; }
send() { # $1 = udp|tcp, $2 = address, $3 = port: one UDP datagram or one TCP SYN
  if [ "$1" = udp ]; then (echo x > "/dev/udp/$2/$3") 2>/dev/null
  else timeout 1 bash -c "echo > /dev/tcp/$2/$3" 2>/dev/null; fi
  true
}
case "$1" in
up)   ip link add "$ifc" type dummy && ip addr add 192.0.2.1/24 dev "$ifc" && ip link set "$ifc" up \
        && ip route add $NET.0/24 dev "$ifc" ;;
tx)   tx ;;
control)
      a=$(tx)
      iptables -I OUTPUT -o "$ifc" -d $NET.99 -p udp --dport 9 -j ACCEPT
      send udp $NET.99 9
      iptables -D OUTPUT -o "$ifc" -d $NET.99 -p udp --dport 9 -j ACCEPT
      echo $(( $(tx) - a )) ;;
handshake)
      host=$(awk '$1=="remote"{print $2; exit}' "$CONF")
      port=$(awk '$1=="remote"{print $3; exit}' "$CONF")
      proto=$(awk '$1=="proto"{print $2; exit}' "$CONF"); case "$proto" in tcp*) proto=tcp ;; *) proto=udp ;; esac
      ip=$(getent ahostsv4 "$host" | awk 'NR==1{print $1}')
      ip route add "$ip/32" dev "$ifc"
      a=$(tx); send "$proto" "$ip" "${port:-1194}"; b=$(tx)
      ip route del "$ip/32" dev "$ifc"
      echo $(( b - a )) ;;
down) ip link del "$ifc" ;;
esac
