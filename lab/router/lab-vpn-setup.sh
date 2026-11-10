#!/bin/bash
# Lab-only: repeat the manual steps of docs/03_OPENVPN_SETUP.md word for word,
# with the lab VPN server's config instead of a Windscribe .ovpn.
set -euo pipefail
mkdir -p /etc/openvpn/client /etc/openvpn/scripts /var/log/openvpn
cp /pki/client.ovpn /etc/openvpn/client/windscribe.conf
# Step 3: the lines the doc says to append, taken from the doc itself so the lab cannot drift.
# (auth-user-pass is skipped: the lab server uses certificates instead of a Windscribe login.)
awk '/Добавьте в конец файла/{f=1;next} f&&/^```/{exit} f&&NF&&!/^#/' /src/docs/03_OPENVPN_SETUP.md \
  >> /etc/openvpn/client/windscribe.conf
echo "--- appended from docs/03:"; sed -n '/^script-security/,$p' /etc/openvpn/client/windscribe.conf
# Steps 4 and 6: up/down scripts and the systemd unit, taken from the doc itself.
DOC=/src/docs/03_OPENVPN_SETUP.md
block_after() { # print the first ```bash/```ini block that follows the line matching $1
  awk -v pat="$1" 'index($0,pat){m=1;next} m==1&&/^```(bash|ini)$/{m=2;next} m==2&&/^```/{exit} m==2' "$DOC"; }
block_after "nano /etc/openvpn/scripts/up.sh" > /etc/openvpn/scripts/up.sh
block_after "nano /etc/openvpn/scripts/down.sh" > /etc/openvpn/scripts/down.sh
block_after "nano /etc/systemd/system/openvpn-windscribe.service" > /etc/systemd/system/openvpn-windscribe.service
for f in /etc/openvpn/scripts/up.sh /etc/openvpn/scripts/down.sh /etc/systemd/system/openvpn-windscribe.service; do
  [ -s "$f" ] || { echo "could not extract $f from docs/03"; exit 1; }
done
chmod +x /etc/openvpn/scripts/*.sh
systemctl daemon-reload
echo "VPN configured as in docs/03"
