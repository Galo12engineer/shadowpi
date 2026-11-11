#!/bin/bash
# Lab-only: give interfaces the names the project expects (eth0 = WAN, wlan0 = hotspot).
set -euo pipefail
rename() { # $1 = address on the interface, $2 = wanted name
  local dev; dev=$(ip -o -4 addr show | awk -v a="$1" '$4 ~ "^"a"/" {print $2}')
  [ "$dev" = "$2" ] && return 0
  ip link set "$dev" down; ip link set "$dev" name "$2"; ip link set "$2" up
}
rename 10.0.0.1 tmp-lan
rename 172.30.0.10 eth0
rename 10.0.0.1 wlan0
# LAB_ISP=1: after install, the ISP gateway is the test 'internet' (whoami)
ip route replace default via "$([ "${LAB_ISP:-0}" = 1 ] && echo 172.30.0.30 || echo 172.30.0.1)" dev eth0
ip -br addr
