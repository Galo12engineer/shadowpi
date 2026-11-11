[RU](LAB.ru.md) · [UA](LAB.ua.md) · **EN**

# Test lab: running ShadowPi without a Raspberry Pi

The lab runs the **real** `scripts/master-install.sh`, the real web panel and the real
firewall scripts in Docker on Debian bookworm **arm64**, the same architecture as a
Raspberry Pi. It then checks every claim the project makes from a client's point of view.

```bash
cd lab
make lab-test     # builds everything from scratch, installs twice, runs 39 checks (~10 min)
make lab-down     # removes the lab
```

Results are written to `lab/out/results.md`, and the logs to `lab/out/`.

## Topology

```
 client 10.0.0.50 ── "Wi-Fi" (lan) ── wlan0 10.0.0.1 [router: real installer, systemd]
                                               eth0 172.30.0.10
                                                 │  (wan)
                         vpnserver 172.30.0.20 ──┤── whoami 198.51.100.7 = "a website on the internet"
                         (OpenVPN, stands in       (answers with the caller's IP; also the ISP gateway
                          for Windscribe)           and a "public DNS" that knows vpn.lab.test)
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
| `master-install.sh` | **Real**, run unchanged with scripted answers | A second run breaks the v2rayA checksum on purpose, see "Lab workarounds" below |
| nginx + PHP panel, sudoers | **Real** | Same paths and permissions as on the Pi |
| `killswitch.sh`, `setup-v2ray-redirect.sh`, `start/stop/restart-all.sh` | **Real** | |
| OpenVPN client | **Real**, configured word for word from docs/03 | A lab OpenVPN server replaces Windscribe |
| Tor, Xray, dnsmasq | **Real** packages | |
| v2rayA | **Real**, installed from the pinned release (check I4) | The remaining checks run on the second install, where v2rayA is refused on purpose (I2), so they show the router works without it |
| V2Ray transparent proxy | **Real Xray core** (installed by the installer) with the docs/04 `dokodemo-door` inbound on :12345 | The outbound is `freedom` instead of a VLESS server; the Xray access log proves which connections went through the proxy |
| Wi-Fi hotspot (hostapd) | **Emulated** | A Docker network named `wlan0` replaces it, so hostapd fails to start |
| 4G modem interfaces | **Emulated** for the kill switch only | Dummy interfaces named `usb0`, `eth1`, `enx…` (`lab/router/lab-4g.sh`); their packet counter shows what the firewall lets out |
| 4G modem, ModemManager, failover | **Not covered** | Needs hardware |
| Reboot | **Emulated** | `docker compose restart router`: systemd boots again, all iptables rules are gone |
| Pi performance, SD card, power | **Not covered** | Needs hardware |

### Lab workarounds

The lab does a few things the real setup does not. Each one is visible in `lab/router/*.sh`
or commented in `lab/lab-test.sh`. None of them changes a project file.

1. **Interface renaming.** The Docker interfaces are renamed to `eth0` and `wlan0`.
2. **`policy-rc.d` removed from the router image.** The debian Docker image forbids apt to
   start services; a real system does not. With the file in place the lab reported a
   "panel 502 after install" that a real install does not have.
3. **Second install with a wrong v2rayA checksum.** In a copy of the installer inside the
   container the pinned SHA-256 values are replaced with zeros, to check that the package is
   refused and the install still finishes.
4. **Xray stand-in for a configured v2rayA** (`lab/router/lab-xray-standin.sh`), described in
   the table above.
5. **Login counter reset after P2.** Every lab request comes from one address, so after the
   lockout test the counter file is removed. That is the same as waiting 5 minutes.
6. **Idle timeout by editing the session file** (P6): `last_activity` is set to 1970 instead
   of waiting an hour.
7. **Dummy 4G interfaces** (`lab/router/lab-4g.sh`) and a **one-name DNS server** on the
   website container, for the kill switch checks K3a, K3b and K6.

The OpenVPN client lines are read from `docs/03_OPENVPN_SETUP.md` itself, so a change to the doc is tested automatically.

## Second round: hotfix (10–11.11.2026)

Each fix was followed by a full lab run from scratch. "Before" is the first-run result.

| ID | Before | Now | What changed |
|---|---|---|---|
| D2 | FAIL | PASS | `log-queries` / `log-dhcp` removed from the dnsmasq config (installer and docs/06). |
| P4 | FAIL | PASS | New session ID at login. One `start_secure_session()` for all entry points: strict mode, `HttpOnly`, `SameSite=Strict`, `Secure` only over HTTPS. |
| P5, P6 | new | PASS | Cookie flags; idle timeout (`SESSION_LIFETIME`) and an absolute lifetime, because the open panel polls every 5 s and would never go idle. |
| P2 | FAIL | PASS | Failed logins are counted in `/var/lib/shadowpi/login-attempts.json` (flock) per client address, with a doubling lockout and a global counter. Checked before the password; fails closed if the file cannot be used. |
| P7 | new | PASS | nginx basic auth in front of the panel used the same password and had no lockout, so P2 could be bypassed through it. First recorded as a FAIL, then the nginx layer was removed: the panel login with its server-side lockout is the only gate. |
| B2 | FAIL | PASS | `start-all.sh`, `stop-all.sh`, `restart-all.sh` exit non-zero when a required step fails; the API returns that exit code. `startWiFi` checks dnsmasq too. |
| B4 | new | PASS | "Switch WAN" reports failure. It also called `wan-switch.sh usb0`, which the script rejects; it now calls `wan-switch.sh switch usb0`. |
| K3 | FAIL | replaced | The check counted rules that name `usb0`/`eth1`/`enx*`. The DROP policy already blocked those interfaces, so there was no leak; the real problem was the opposite (see K3b). Replaced by K3a and K3b, which test behaviour on dummy interfaces. |
| K3a | new | PASS | Nothing from the router or a client leaves through a 4G interface while the VPN is down. |
| K3b | new | PASS | The VPN handshake is allowed through a 4G interface. Before the fix it was allowed on `eth0`/`wwan0` only, so failover could not bring the VPN up. The rules no longer name WAN interfaces. |
| K2 | FAIL | PASS | The router may contact only the VPN server's own address, port and protocol, read from the `remote` lines. |
| K6 | new | PASS | With a hostname in `remote` (what providers ship) the VPN could not reconnect under the kill switch at all: the router's DNS is blocked. The script now resolves the name when it runs and pins it in the rules and in `/etc/hosts`. Trade-offs: docs/08. |
| K5 | new | PASS | Nothing applied the kill switch at boot. Shown by disabling the new unit and rebooting the lab router: no DROP policies, and the website saw the client itself (`10.0.0.50`). The installer now enables `shadowpi-killswitch.service` (`Before=network-pre.target`). |
| I3 | FAIL | PASS | Mostly a lab artefact: the debian Docker image forbids apt to start services (`policy-rc.d`). Removed from the lab image; the installer also starts php-fpm explicitly now. |
| D1 | PASS | PASS | **Broke when the lab was made realistic, then fixed.** With services started by apt, systemd-resolved holds `127.0.0.53:53` before dnsmasq starts, and dnsmasq (binding all addresses) failed: no DNS and no DHCP for clients. The old lab hid this. Fixed with `bind-dynamic`. |
| I2 | FAIL | PASS | `rfkill` is installed and its failure is a warning. The check now also breaks the v2rayA checksum on purpose and expects the installer to refuse the package and still finish. |
| I1 | FAIL | PASS | v2rayA is optional and no longer comes from `apt.v2raya.org` (its certificate chain is not trusted by Debian; TLS checks are not disabled). A pinned release is installed only if its SHA-256 matches. |
| I4 | new | PASS | v2rayA really is installed from the pinned release and runs. |
| I5 | new | PASS | The installer does not print the Wi-Fi or panel password and does not pass the panel password as a process argument; the files that hold them are not world-readable. |
| T1 | FAIL | **FAIL** | Not fixed on purpose: Tor "Paranoid" mode still does not route traffic. It is now labelled experimental in README, ARCHITECTURE, `toggle-tor.sh` and the panel (T2). Roadmap. |
| T2 | new | PASS | The labels are there. |

Also fixed without a lab check: the log view and the WAN list in the panel no longer use
`innerHTML` (stored XSS through log content), and a dead "local network" check was removed
from `api.php`.

Two findings were about the lab itself, not the project: the K3 check asked the wrong
question, and the Docker image's `policy-rc.d` both invented I3 and hid D1. Both are fixed
in the lab, in commits of their own.

## Final run

`cd lab && ./lab-test.sh`, from scratch, on the final state of this branch. Evidence for
every line (what the website saw, what the panel answered) is in `lab/out/results.md`.

| ID | Result | Check |
|---|---|---|
| I1 | PASS | Installer finishes on Debian bookworm arm64 |
| I4 | PASS | v2rayA is installed from the pinned release (SHA-256 checked) and runs |
| I2 | PASS | Installer refuses v2rayA with a wrong SHA-256 and still finishes |
| I5 | PASS | Installer does not print the Wi-Fi or panel password, and keeps them in non-world-readable files |
| I3 | PASS | Panel API answers right after install (before reboot) |
| P1 | PASS | API refuses requests without login |
| P2 | PASS | 6 wrong passwords (new cookie each) lock the login |
| P7 | PASS | Panel password cannot be guessed without limit through nginx basic auth |
| P3 | PASS | Write action without CSRF token is refused |
| P4 | PASS | Session ID changes at login (no session fixation) |
| P5 | PASS | Session cookie is HttpOnly and SameSite=Strict |
| P6 | PASS | Idle session expires (SESSION_LIFETIME) |
| V1 | PASS | Client reaches the internet through the VPN (docs config) |
| V2 | PASS | Panel shows the VPN IP |
| V3.80 | PASS | Client → site:80 goes through the VPN |
| V3.8000 | PASS | Client → site:8000 goes through the VPN |
| B1 | PASS | 'Start all' runs the whole start script |
| B2 | PASS | 'Start all' reports failure when steps fail |
| B4 | PASS | 'Switch WAN' to a missing interface reports failure |
| X3 | PASS | 'Start all' does not cut clients off when the proxy is not running |
| D1 | PASS | Client DNS works through the router |
| D2 | PASS | Router does not log clients' DNS queries |
| B3 | PASS | 'Restart all' restarts services |
| T1 | **FAIL** | Tor 'Paranoid' mode sends client traffic into Tor |
| T2 | PASS | While T1 fails, Tor mode is labelled experimental (toggle-tor.sh output and panel) |
| X1 | PASS | V2Ray redirect script applies cleanly when the proxy listens |
| X4 | PASS | Running the script twice leaves one rule set |
| X2.80 | PASS | Client → site:80 goes through V2Ray, then the VPN |
| X2.443 | PASS | Client → site:443 goes through V2Ray, then the VPN |
| X2.8000 | PASS | Client → site:8000 goes through V2Ray, then the VPN |
| X5 | PASS | Panel on the router stays reachable (not sent to the proxy) |
| K1.80 | PASS | VPN down: client cannot reach site:80 |
| K1.8000 | PASS | VPN down: client cannot reach site:8000 |
| K2 | PASS | VPN down: router itself cannot reach the internet on tcp/443 |
| K3a | PASS | VPN down: nothing leaves through a 4G interface (usb0, eth1, enx*) |
| K3b | PASS | VPN handshake is allowed through a 4G interface (so failover can bring the VPN up) |
| K4 | PASS | IPv6 disabled and blocked |
| K6 | PASS | VPN reconnects under the kill switch when 'remote' is a hostname |
| K5 | PASS | After a reboot the kill switch is on before anything else starts |

PASS 38 · FAIL 1 · 2026-11-11 10:41 UTC

The one remaining FAIL (T1) is known and deliberate: the lab states the correct behaviour
and the project does not do it yet. It is in [ROADMAP.md](ROADMAP.md).

Progress: first run 8 PASS / 16 FAIL → V1 fix 9 / 15 → path fix, plus the new check X3: 12 / 13 (25 checks) → V2Ray fix, plus X4 and X5: 19 / 10 (29 checks) → hotfix round, plus 12 new checks and K3 split in two: 37 / 2 (39 checks) → nginx basic auth removed (P7): **38 PASS / 1 FAIL (39 checks)**.

## History: findings from the first run (10.11.2026)

This is the state before the hotfix round, kept as a record. The current state is in the two sections above.

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

At the end of the first round: 19 PASS / 10 FAIL (29 checks).
