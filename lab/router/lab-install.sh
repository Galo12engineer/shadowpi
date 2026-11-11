#!/bin/bash
# Lab-only: run the project's real installer, answering its prompts.
# Answers: SSID, Wi-Fi password, panel password, WAN=1 (eth0), Tor=y, confirm=y
# LAB_BAD_V2RAYA_SHA=1 replaces the pinned v2rayA SHA-256 values with zeros in the lab copy,
# to check that the installer refuses the package and still finishes. v2rayA is optional.
# The project files are not modified.
cd /tmp && rm -rf shadowpi && cp -r /src shadowpi
if [ "${LAB_BAD_V2RAYA_SHA:-0}" = 1 ]; then
  sed -i -E 's/^(V2RAYA_SHA256_[a-z0-9]+)="[0-9a-f]+"/\1="0000000000000000000000000000000000000000000000000000000000000000"/' shadowpi/scripts/master-install.sh
  grep -c '^V2RAYA_SHA256_.*="0\{64\}"' shadowpi/scripts/master-install.sh | sed 's/^/lab: v2rayA hashes replaced: /'
fi
printf 'ShadowLab\nlabwifi123\nlabpanel123\n1\ny\ny' | bash shadowpi/scripts/master-install.sh
