# ShadowPi: a privacy router for Raspberry Pi

<p align="center">
  <img src="docs/project-banner.png" alt="ShadowPi architecture" width="600">
</p>

ShadowPi turns a Raspberry Pi 4 into a Wi-Fi router that sends every connected device through a chain of VPN, obfuscation proxy and, optionally, Tor. A kill switch blocks traffic whenever the tunnel is down.

> **Status:** design, install scripts and web panel are complete. The project has **not yet been validated end to end on real hardware**. Treat it as a reference build. Detailed setup docs are in Russian.

## How traffic flows

**Fast mode (default)**

```
Device → Wi-Fi (hostapd) → OpenVPN → V2Ray/Xray proxy → Internet
```

**Paranoid mode (+ Tor)**

```
Device → Wi-Fi → OpenVPN → Tor → V2Ray/Xray proxy → Internet
```

The proxy hop always comes last, so a Tor exit node sees only encrypted proxy traffic, not the user's traffic.

## Features

| Area | What it does |
|---|---|
| Tunnels | OpenVPN as the base tunnel, V2Ray/Xray for obfuscation, optional Tor layer (`toggle-tor.sh fast\|paranoid`) |
| Leak protection | iptables kill switch, DNS leak protection, IPv6 disabled, transparent proxy redirect |
| Uplinks | Ethernet or a USB 4G/LTE modem, with WAN switching (`wan-switch.sh`) and modem setup via ModemManager |
| Hotspot | hostapd + dnsmasq, local `anonrouter.local` name |
| Web panel | nginx + PHP control panel on port 8080 |
| Testing | `test-all.sh`: public IP, DNS and IPv6 leaks, service status, VPN and hotspot checks, firewall rules |

## Web panel security

- **Two layers of auth:** nginx basic auth in front, and a PHP session login behind it (bcrypt hash set by the installer).
- **Default-deny API:** every action needs an authenticated session. Hotspot clients share the router's LAN, so "local network" is not treated as trusted.
- **State-changing actions** accept POST only, with a CSRF token and per-session rate limiting.
- **Least-privilege sudo:** `www-data` may run only a fixed list of `systemctl` units and root-owned scripts (`/etc/sudoers.d/shadowpi`, checked with `visudo`).
- Whitelisted inputs for services, WAN targets and modem setup; shell arguments go through `escapeshellarg`.
- Security headers (CSP, `X-Frame-Options`, `nosniff`) and an action log.

## Requirements

| Component | Requirement |
|---|---|
| Hardware | Raspberry Pi 4 (2 GB+ RAM) |
| OS | Raspberry Pi OS Lite 64-bit or DietPi |
| WAN | Ethernet or a USB 4G/LTE modem |
| LAN | Built-in Wi-Fi (`wlan0`) |
| Accounts | An OpenVPN provider config and a V2Ray/Xray server |

## Install

```bash
ssh <user>@raspberrypi.local
git clone https://github.com/Galo12engineer/shadowpi.git
cd shadowpi
sudo bash scripts/master-install.sh
```

The installer asks for the Wi-Fi name and password and the panel password, then sets up the hotspot, nginx + PHP, the scripts in `/opt/shadowpi/scripts` and the sudo rules. After that, copy your OpenVPN config and add a V2Ray server (see `docs/03_OPENVPN_SETUP.md` and `docs/04_V2RAY_SETUP.md`).

| Panel | URL |
|---|---|
| ShadowPi | `http://anonrouter.local:8080` |
| v2rayA | `http://anonrouter.local:2017` |

## Repository layout

```
scripts/   install, start/stop, kill switch, Tor toggle, WAN switch, modem setup, tests
web-ui/    control panel (HTML/JS front end, PHP API and auth)
docs/      step-by-step guides 00–11 (hardware → troubleshooting), in Russian
```

## Disclaimer

This is an educational project. Use it in line with the laws of your country and the terms of your VPN and proxy providers.

## License

MIT, see [LICENSE](LICENSE).
