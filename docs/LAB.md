# Test lab: running ShadowPi without a Raspberry Pi

The lab runs the **real** `scripts/master-install.sh`, the real web panel and the real
firewall scripts in Docker on Debian bookworm **arm64**, the same architecture as a
Raspberry Pi. It then checks every claim the project makes from a client's point of view.

```bash
cd lab
make lab-test     # builds everything from scratch, installs, runs 29 checks (~5 min)
make lab-down     # removes the lab
```

Results are written to `lab/out/results.md`, and the logs to `lab/out/`.

## Topology

```
 client 10.0.0.50 ── "Wi-Fi" (lan) ── wlan0 10.0.0.1 [router: real installer, systemd]
                                               eth0 172.30.0.10
                                                 │  (wan)
                         vpnserver 172.30.0.20 ──┤── whoami 198.51.100.7 = "a website on the internet"
                         (OpenVPN, stands in       (answers with the caller's IP; also the ISP gateway)
                          for Windscribe)
```

The website reports which IP it sees:

| Website sees | Meaning |
|---|---|
| `172.30.0.20` | The traffic went through the VPN. This is correct. |
| `172.30.0.10` | The router's real WAN IP. This is a leak. |
| `10.0.0.50` | The client itself. This is a leak. |
| `none` | The traffic was blocked. |

## What is real and what is emulated

| Part | In the lab | Notes |
|---|---|---|
| `master-install.sh` | **Real**, run with scripted answers | Two lab-only workarounds, see "Lab workarounds" below |
| nginx + PHP panel, sudoers | **Real** | Same paths and permissions as on the Pi |
| `killswitch.sh`, `setup-v2ray-redirect.sh`, `start/stop/restart-all.sh` | **Real** | |
| OpenVPN client | **Real**, configured word for word from docs/03 | A lab OpenVPN server replaces Windscribe |
| Tor, Xray, dnsmasq | **Real** packages | |
| v2rayA | **Not installed** | Its apt repo fails TLS on bookworm (check I1) |
| V2Ray transparent proxy | **Real Xray core** (installed by the installer) with the docs/04 `dokodemo-door` inbound on :12345 | The outbound is `freedom` instead of a VLESS server; the Xray access log proves which connections went through the proxy |
| Wi-Fi hotspot (hostapd) | **Emulated** | A Docker network named `wlan0` replaces it, so hostapd fails to start |
| 4G modem, ModemManager | **Not covered** | Needs hardware |
| Pi performance, SD card, power | **Not covered** | Needs hardware |

### Lab workarounds

The lab does a few things the real setup does not. Each one is visible in `lab/router/*.sh`.

1. **Interface renaming.** The Docker interfaces are renamed to `eth0` and `wlan0`.
2. **v2rayA skipped on the second install run.** Only the v2rayA block is removed, and only in a copy of the installer inside the container.
3. **`php8.2-fpm` started by hand.** The installer asks for a reboot at the end; this does what the reboot would do.
4. **Xray stand-in for v2rayA** (`lab/router/lab-xray-standin.sh`), described in the table above.

The OpenVPN client lines are read from `docs/03_OPENVPN_SETUP.md` itself, so a change to the doc is tested automatically.

## Findings from the first run (10.11.2026)

The table below is a summary. `lab/out/results.md` has the evidence for each check.

| ID | Result | Finding |
|---|---|---|
| I1 | FAIL | The v2rayA apt repo uses a Let's Encrypt **YE2** chain that bookworm's CA store does not trust, so the installer stops. |
| I2 | FAIL | `rfkill` is not installed on plain Debian, so the installer aborts on its last step. Raspberry Pi OS usually ships it. |
| I3 | FAIL | Right after install the panel returns 502 because php-fpm is not started. It works after a reboot. |
| P2 | FAIL | Login lockout lives in the PHP session. Dropping the cookie resets it, so password guessing is unlimited. |
| P4 | FAIL | The session ID is not regenerated at login (session fixation). |
| V1 | ✅ fixed | With the docs' `pull-filter ignore "redirect-gateway"`, clients had **no internet** while the VPN was up: the default route stayed on `eth0` and the kill switch dropped it. docs/03 now uses `redirect-gateway def1`, and K1 still passes. |
| V2 | ✅ fixed | The up/down scripts in docs/03 wrote to `/opt/anon-router/status/`, but the panel reads `/opt/shadowpi/status/`, so the VPN IP was never shown. All 71 `/opt/anon-router` and `/var/log/anon-router` paths in scripts and docs now point to the installed paths. |
| D2 | FAIL | `dnsmasq` is installed with `log-queries`, so every client DNS query is logged on a privacy router. |
| B1, B3 | ✅ fixed | `start-all.sh` and `restart-all.sh` called `/opt/anon-router/scripts/...`, which does not exist, so "Restart all" did nothing. Fixed together with V2. |
| B2 | FAIL | The panel answers `success: true` even when the script failed (v2raya missing, hostapd failing). |
| X3 | ✅ fixed | "Start all" applied the V2Ray redirect even when nothing listened on port 12345, so every client TCP connection except ports 80/443 died (this was hidden until B1 was fixed). The script now refuses and clients stay on the VPN. |
| T1 | FAIL | "Paranoid" Tor mode starts Tor, but no rule sends client traffic into it, so traffic is unchanged. |
| X1 | ✅ fixed | There was a typo `-j RET URN` in `setup-v2ray-redirect.sh`. The script is rewritten and is now the single source; docs/04 points to it instead of carrying its own copy. |
| X2 | ✅ fixed | The redirect skipped destination **ports** 80/443, which is almost all web traffic. It now skips destination **addresses** (the router itself, private ranges). Proven by the Xray access log for ports 80, 443 and 8000. |
| X4 | ✅ new, PASS | The script is idempotent: running it twice leaves one rule set. The old one added a duplicate PREROUTING jump on every run. |
| X5 | ✅ new, PASS | The panel on the router stays reachable from Wi-Fi and is not sent to the proxy. |
| — | ✅ fixed | Even with V2Ray running, the kill switch's INPUT policy DROP would have discarded the redirected connections to :12345. The script now opens that port on `wlan0`. |
| — | open | docs/08_FIREWALL.md describes two more firewall variants (`iptables-killswitch.sh`, nftables) that disagree with `scripts/killswitch.sh`. |
| K2 | FAIL | When the VPN is down, the **router itself** still reaches any host on tcp/443 with its real IP, because the kill switch allows `-o eth0 --dport 443` to every destination. |
| K3 | FAIL | The kill switch covers `eth0` and `wwan0` only. The 4G names `wan-switch.sh` actually uses (`usb0`, `eth1`, `enx*`) are not covered. |
| — | FAIL | The docs tell the user to create 9 scripts that are not in the repo (`wan-failover.sh`, `route-through-tor.sh`, `connect-4g.sh`, …). There is no lab check for this yet. |
| P1, P3, V3, D1, K1, K4 | PASS | These work: auth gate, CSRF, VPN routing (after the fix), DNS, the client kill switch, and IPv6 blocking. |

The client-side kill switch works: with the VPN stopped, nothing from the hotspot leaks (K1).

Progress: first run 8 PASS / 16 FAIL → V1 fix 9 / 15 → path fix, plus the new check X3: 12 PASS / 13 FAIL (25 checks) → V2Ray fix, plus the new checks X4 and X5: 19 PASS / 10 FAIL (29 checks).
