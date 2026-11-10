#!/bin/bash
# Lab-only: run the project's real installer, answering its prompts.
# Answers: SSID, Wi-Fi password, panel password, WAN=1 (eth0), Tor=y, confirm=y
# LAB_SKIP_V2RAYA=1 removes only the v2rayA block from the lab copy (its apt repo
# fails TLS on Debian bookworm, see docs/LAB.md). The project files are not modified.
cd /tmp && rm -rf shadowpi && cp -r /src shadowpi
if [ "${LAB_SKIP_V2RAYA:-0}" = 1 ]; then
  sed -i '/Установка v2rayA/,/systemctl start v2raya/d' shadowpi/scripts/master-install.sh
fi
printf 'ShadowLab\nlabwifi123\nlabpanel123\n1\ny\ny' | bash shadowpi/scripts/master-install.sh
