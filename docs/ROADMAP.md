# Roadmap

What the lab-verified hotfix round (branch `fix/lab-verified-routing`) fixed is listed in
[LAB.md](LAB.md). This file lists what it left out, why each item matters, and what "done"
means. Items marked **FAIL in the lab** have a check that fails today on purpose.

## Security

| # | Item | Why it matters | Done when |
|---|---|---|---|
| 1 | **nginx basic auth has no lockout** (lab P7, FAIL) | It sits in front of the panel and uses the same password as the PHP login. nginx answers 401 for a wrong password and 200 for the right one, forever, so the server-side lockout (P2) can be bypassed through it. `limit_req` does not help: it would have to limit attempts, and the panel itself sends several requests every 5 s. | Either basic auth is removed (one login with a real lockout), or failed basic-auth attempts are banned (fail2ban on the nginx error log). P7 passes. |
| 2 | **Tor "Paranoid" mode does not route traffic** (lab T1, FAIL) | The mode only starts the Tor service. It is labelled experimental everywhere (lab T2), but the feature is missing. | `nat PREROUTING -i wlan0`: tcp → TransPort 9040, udp/53 → DNSPort 5353, other UDP dropped; INPUT opened for both ports on `wlan0`; works together with the `V2RAY` chain in the same hook; fails closed when Tor is not bootstrapped. Lab: client traffic reaches TransPort, and with a private Tor network (chutney) the website sees a Tor exit. |
| 3 | **HTTPS for the panel** | The panel runs on plain HTTP, so the password and the session cookie cross the hotspot unencrypted, readable by any other client that knows the Wi-Fi password. The `Secure` cookie flag is already set automatically once requests arrive over TLS. | nginx serves the panel on 443 with a locally generated certificate; 8080 redirects. |
| 4 | **SSH is open on `eth0`** | `killswitch.sh` accepts tcp/22 on the WAN-side Ethernet. Fine behind a home router, wrong on an untrusted LAN. | SSH is accepted on the hotspot only by default, with a documented switch for the wired side. |
| 5 | **CSP still allows `'unsafe-inline'`** | `index.html` uses inline `onclick` handlers, so the policy cannot forbid inline script. The log view and WAN list no longer use `innerHTML`, but there is no automated XSS check. | Handlers move to `app.js`, the CSP drops `'unsafe-inline'`, a headless-browser lab check injects markup into a log line. |
| 6 | **Xray is installed with `curl … \| bash` from a branch** | Whatever is on that branch at install time runs as root. v2rayA is already pinned by version and SHA-256; Xray is not. | The Xray release is pinned and its checksum verified before it runs. |
| 7 | **API rate limit is per session** | `check_rate_limit()` counts in `$_SESSION`, the same weakness the login lockout had. Low impact: it only applies after login. | Counters move to the server-side store used for the login lockout. |
| 8 | **Pinned VPN addresses are refreshed only when `killswitch.sh` runs** | If the provider moves the server while the VPN is down, the VPN cannot reconnect until the script is run again (see docs/08). | A timer re-resolves the `remote` hostnames while the VPN is up and updates the rules. |
| 9 | **First-setup DNS lookup needs a real resolver in `/etc/resolv.conf`** | With the systemd-resolved stub (`127.0.0.53`) the one-time lookup in `killswitch.sh` cannot work, because the query is sent by another process. | The script detects the stub and uses resolved's upstream servers, or says clearly what to do. |

## Firewall

- **docs/08 describes three firewalls.** Only `scripts/killswitch.sh` is installed and
  tested. The nftables config and the `iptables-killswitch.sh` example in the same doc
  disagree with it and with each other. Remove them or generate them from one source.
- **Migrate to nftables.** One atomic `nft -f` load instead of a sequence of `iptables`
  commands (today there is a short moment between "flush" and "last rule added"), a named
  set for the VPN endpoints, counters per rule. Run both rule sets through the lab until
  every check gives the same result, then drop iptables.

## Features that are not verified or not finished

- **4G failover.** `wan-switch.sh failover` and `auto` decide that a WAN is alive by pinging
  `8.8.8.8` through it, which the kill switch drops, so the test always fails with the kill
  switch on. The lab only has dummy interfaces (K3a, K3b). Needs a different liveness test
  (link state, or the VPN handshake itself) and a real modem.
- **V2Ray layer end to end.** v2rayA is installed from a pinned release (I4), but the
  transparent-proxy checks (X1–X5) run against an Xray stand-in with a `freedom` outbound.
  A real VLESS server and a v2rayA-managed config are not covered.
- **Wi-Fi hotspot.** `hostapd` cannot run in Docker; the lab replaces the radio with a Docker
  network. WPA2, client isolation and performance need hardware.
- **Scripts the docs mention but the repo does not have** (the docs tell the reader to
  create them by hand): `wan-failover.sh`, `connect-4g.sh`, `vpn-route-4g.sh`
  (docs/07), `route-through-tor.sh`, `switch-mode.sh` (docs/05), `iptables-killswitch.sh`,
  `firewall-stats.sh` (docs/08), `start-wifi.sh` (docs/06), `check-packages.sh` (docs/02),
  `collect-diagnostics.sh` (docs/11). Each one should either be added to `scripts/` and
  tested, or removed from the docs.
- **`openvpn-systemd-resolved` is installed but not used.** The up/down scripts in docs/03
  write `/etc/resolv.conf` directly. The package pulls in systemd-resolved, which caused the
  dnsmasq port conflict (lab D1) and complicates the first-setup lookup (item 9 above).
  Either use it properly or stop installing it.
- **docs/11 still suggests `rc.local`** for the kill switch. The installer now enables
  `shadowpi-killswitch.service`; the doc should say that instead.
- **Real hardware.** Nothing here has run on a Raspberry Pi. The lab covers logic, not
  radio, modem, SD card or power.

## Tooling

- **CI.** Run `lab/lab-test.sh` on GitHub Actions (arm64 runner; the router container needs
  `privileged` and systemd), upload `lab/out/` as an artifact, and fail the job on any FAIL
  that is not on a short list of known ones (today: T1, P7).
- **Exit code.** `lab-test.sh` always exits 0; it should exit non-zero on an unexpected FAIL.
- **Static checks in CI:** `shellcheck` for `scripts/` and `lab/`, `php -l` for `web-ui/`.
- **Docs language.** The step-by-step docs are in Russian, the newer sections in English.
