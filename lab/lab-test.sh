#!/bin/bash
# End-to-end test of ShadowPi on Debian arm64 without a Raspberry Pi.
# Builds the lab from scratch, runs the REAL installer and scripts, then checks each claim.
# Every check states the CORRECT behaviour; FAIL means the project does not do it yet.
set -uo pipefail
cd "$(dirname "$0")"
mkdir -p out; RES=out/results.md; : > "$RES"
SITE=198.51.100.7 VPN_EXIT=172.30.0.20 ROUTER_WAN=172.30.0.10
R() { docker compose exec -T router bash -c "$1"; }
C() { docker compose exec -T client sh -c "$1"; }
pass=0 fail=0
check() { # $1 id, $2 description, $3 0=ok, $4 evidence
  local s=PASS; [ "$3" = 0 ] && pass=$((pass+1)) || { s=FAIL; fail=$((fail+1)); }
  printf '%-4s %-5s %s — %s\n' "$1" "$s" "$2" "$4"
  printf '| %s | %s | %s | %s |\n' "$1" "$s" "$2" "$(echo "$4" | tr '|\n' '/ ')" >> "$RES"
}
site_from_client() { C "curl -s -m 6 http://$SITE:$1/ || echo none"; }
panel() { # $1 action, $2 extra POST data; logs in once, uses CSRF for writes
  R "J=/tmp/jar; B='-s -m 90 -u admin:labpanel123 -c \$J -b \$J'
     [ -s \$J ] || curl \$B -X POST -d 'action=login&username=admin&password=labpanel123' http://10.0.0.1:8080/auth.php >/dev/null
     T=\$(curl \$B 'http://10.0.0.1:8080/api.php?action=get_csrf' | sed 's/.*\"token\":\"\([^\"]*\)\".*/\1/')
     curl \$B -X POST -d \"action=$1&csrf_token=\$T${2:-}\" http://10.0.0.1:8080/api.php"; }

echo "== Building lab from scratch"
docker compose down -v >/dev/null 2>&1; docker compose up -d --build >/dev/null 2>&1 || { echo "compose up failed"; exit 1; }
for i in $(seq 30); do [ "$(R 'systemctl is-system-running' 2>/dev/null)" = running ] && break; sleep 2; done
R "chmod 755 /usr/local/sbin/lab-*.sh; lab-netprep.sh" >/dev/null

echo "== Running the real master-install.sh (a few minutes)"
R "lab-install.sh" > out/install-as-is.log 2>&1; rc=$?
check I1 "Installer finishes on Debian bookworm arm64" $rc "exit $rc; $(grep -m1 -o 'Certificate verification failed[^.]*' out/install-as-is.log)"
echo "   retrying with the v2rayA block removed (lab copy only)"
docker compose up -d --force-recreate router >/dev/null 2>&1; sleep 6
for i in $(seq 30); do [ "$(R 'systemctl is-system-running' 2>/dev/null)" = running ] && break; sleep 2; done
R "chmod 755 /usr/local/sbin/lab-*.sh; lab-netprep.sh" >/dev/null
R "LAB_SKIP_V2RAYA=1 lab-install.sh" > out/install.log 2>&1; rc=$?
check I2 "Installer finishes without v2rayA" $rc "exit $rc; $(tail -1 out/install.log)"
code=$(R "curl -s -o /dev/null -w '%{http_code}' -u admin:labpanel123 'http://10.0.0.1:8080/api.php?action=vpn_status'")
check I3 "Panel API answers right after install (before reboot)" $([ "$code" = 401 ] || [ "$code" = 200 ]; echo $?) "HTTP $code (php-fpm: $(R 'systemctl is-active php8.2-fpm'))"
R "systemctl start php8.2-fpm"   # what a reboot would do
R "LAB_ISP=1 lab-netprep.sh" >/dev/null

echo "== Panel security"
out=$(R "curl -s -u admin:labpanel123 'http://10.0.0.1:8080/api.php?action=vpn_status'")
check P1 "API refuses requests without login" $(echo "$out" | grep -q 'Authentication required'; echo $?) "$out"
out=$(R "curl -s -u admin:labpanel123 -X POST -d 'action=vpn_status' http://10.0.0.1:8080/api.php")
lock=$(R "for i in 1 2 3 4 5 6; do curl -s -u admin:labpanel123 -X POST -d 'action=login&username=admin&password=wrong\$i' http://10.0.0.1:8080/auth.php >/dev/null; done
          curl -s -u admin:labpanel123 -X POST -d 'action=login&username=admin&password=labpanel123' http://10.0.0.1:8080/auth.php")
check P2 "6 wrong passwords (new cookie each) lock the login" $(echo "$lock" | grep -q '"success":true'; [ $? != 0 ]; echo $?) "after 6 failures the correct password still gives: $lock"
out=$(R "J=/tmp/j2; curl -s -u admin:labpanel123 -c \$J -b \$J -X POST -d 'action=login&username=admin&password=labpanel123' http://10.0.0.1:8080/auth.php >/dev/null; curl -s -u admin:labpanel123 -b \$J -X POST -d 'action=tor_start' http://10.0.0.1:8080/api.php")
check P3 "Write action without CSRF token is refused" $(echo "$out" | grep -q 'Invalid CSRF'; echo $?) "$out"
sess=$(R "J=/tmp/j3; curl -s -u admin:labpanel123 -c \$J 'http://10.0.0.1:8080/auth.php?action=check' >/dev/null; a=\$(awk '/shadowpi_session/{print \$7}' \$J); curl -s -u admin:labpanel123 -b \$J -c \$J -X POST -d 'action=login&username=admin&password=labpanel123' http://10.0.0.1:8080/auth.php >/dev/null; b=\$(awk '/shadowpi_session/{print \$7}' \$J); [ \"\$a\" != \"\$b\" ] && echo changed || echo same")
check P4 "Session ID changes at login (no session fixation)" $([ "$sess" = changed ]; echo $?) "session id $sess"

echo "== VPN configured exactly as docs/03_OPENVPN_SETUP.md says"
R "lab-vpn-setup.sh && systemctl start openvpn-windscribe && /opt/shadowpi/scripts/killswitch.sh" > out/vpn-ks.log 2>&1
sleep 8
got=$(site_from_client 8000)
check V1 "Client reaches the internet through the VPN (docs config)" $([ "$got" = "$VPN_EXIT" ]; echo $?) "website saw: $got"
ip=$(R "J=/tmp/jv; rm -f \$J; B='-s -u admin:labpanel123 -c \$J -b \$J'; curl \$B -X POST -d 'action=login&username=admin&password=labpanel123' http://10.0.0.1:8080/auth.php >/dev/null; curl \$B 'http://10.0.0.1:8080/api.php?action=vpn_status'; echo; ls /opt/shadowpi/status/ /opt/anon-router/status/ 2>&1 | tr '\n' ' '")
check V2 "Panel shows the VPN IP" $(echo "$ip" | grep -q '"ip":"10\.8'; echo $?) "$ip"

for p in 80 8000; do got=$(site_from_client $p); check "V3.$p" "Client → site:$p goes through the VPN" $([ "$got" = "$VPN_EXIT" ]; echo $?) "website saw: $got"; done

echo "== Panel buttons"
sa=$(panel start_all); sleep 3
sa_err=$(R "/opt/shadowpi/scripts/start-all.sh 2>&1 | grep -E -i 'no such file|not found|bad argument|failed' | head -3")
check B1 "'Start all' runs the whole start script" $(echo "$sa_err" | grep -q -i 'no such file'; [ $? != 0 ]; echo $?) "$(echo "$sa_err" | grep -i -m1 'no such file' || echo 'all steps found')"
check B2 "'Start all' reports failure when steps fail" $( [ -n "$sa_err" ] && echo "$sa" | grep -q '"success":true'; [ $? != 0 ]; echo $?) "panel said $(echo "$sa" | grep -o '"success":[a-z]*'), script errors: $(echo $sa_err)"
got=$(site_from_client 8000); red=$(R "iptables -t nat -S PREROUTING | grep -c V2RAY")
check X3 "'Start all' does not cut clients off when the proxy is not running" $([ "$got" = "$VPN_EXIT" ] && [ "$red" = 0 ]; echo $?) "website saw: $got; redirect rules applied: $red"
dns=$(C "nslookup -timeout=3 example.com 10.0.0.1 2>&1 | grep -c 'Address: [0-9]' ")
check D1 "Client DNS works through the router" $([ "${dns:-0}" -ge 1 ]; echo $?) "answers: $dns"
logged=$(R "journalctl -u dnsmasq --no-pager | grep -c 'query\[A\] example.com'")
check D2 "Router does not log clients' DNS queries" $([ "${logged:-0}" = 0 ]; echo $?) "$logged query lines for example.com in the journal (dnsmasq log-queries)"
R "systemctl stop tor"; ra=$(panel restart_all); sleep 3
rs=$(R "/opt/shadowpi/scripts/restart-all.sh 2>&1 | grep -m1 'No such file'")
check B3 "'Restart all' restarts services" $([ -z "$rs" ]; echo $?) "$rs"
panel tor_start >/dev/null; sleep 5
got=$(site_from_client 8000); nat=$(R "iptables -t nat -S | grep -c -E '9040|5353'")
check T1 "Tor 'Paranoid' mode sends client traffic into Tor" $([ "${nat:-0}" -gt 0 ]; echo $?) "tor: $(R 'systemctl is-active tor'), NAT rules to Tor ports: $nat, website still saw: $got"
echo "== V2Ray transparent proxy (lab Xray stand-in on :12345)"
R "lab-xray-standin.sh" > out/xray.log 2>&1
v2=$(R "/opt/shadowpi/scripts/setup-v2ray-redirect.sh 2>&1; echo rc=\$?")
check X1 "V2Ray redirect script applies cleanly when the proxy listens" $(echo "$v2" | grep -q 'rc=0'; echo $?) "$(echo $v2)"
R "/opt/shadowpi/scripts/setup-v2ray-redirect.sh >/dev/null 2>&1"
jumps=$(R "iptables -t nat -S PREROUTING | grep -c V2RAY")
check X4 "Running the script twice leaves one rule set" $([ "$jumps" = 1 ]; echo $?) "PREROUTING jumps to V2RAY: $jumps"
R ": > /var/log/xray/access.log"
for p in 80 443 8000; do
  got=$(site_from_client $p); sleep 1; seen=$(R "grep -c '$SITE:$p' /var/log/xray/access.log")
  check "X2.$p" "Client → site:$p goes through V2Ray, then the VPN" $([ "$got" = "$VPN_EXIT" ] && [ "${seen:-0}" -ge 1 ]; echo $?) "website saw: $got; Xray access log entries: $seen"
done
code=$(C "curl -s -o /dev/null -w '%{http_code}' -m5 http://10.0.0.1:8080/")
check X5 "Panel on the router stays reachable (not sent to the proxy)" $([ "$code" = 401 ]; echo $?) "HTTP $code (401 = nginx basic auth answered)"
R "/opt/shadowpi/scripts/killswitch.sh >/dev/null 2>&1"   # back to a clean ruleset

echo "== Kill switch: VPN stopped from the panel"
panel vpn_stop >/dev/null; sleep 4
for p in 80 8000; do got=$(site_from_client $p); check "K1.$p" "VPN down: client cannot reach site:$p" $([ "$got" = none ]; echo $?) "website saw: $got"; done
got=$(R "curl -s -m5 http://$SITE:443/ || echo none")
check K2 "VPN down: router itself cannot reach the internet on tcp/443" $([ "$got" = none ]; echo $?) "website saw: $got (real WAN IP is $ROUTER_WAN)"
cov=$(R "iptables -S OUTPUT | grep -c -E -- '-o (usb0|usb1|eth1|enx)'")
check K3 "Kill switch also covers the 4G interfaces wan-switch.sh uses" $([ "${cov:-0}" -gt 0 ]; echo $?) "rules for usb0/usb1/eth1/enx*: $cov (only eth0 and wwan0 are covered)"
v6=$(R "sysctl -n net.ipv6.conf.all.disable_ipv6; ip6tables -S | grep -c -- '-P .* DROP'")
check K4 "IPv6 disabled and blocked" $(echo "$v6" | tr '\n' ' ' | grep -q '^1 3'; echo $?) "disable_ipv6 / DROP policies: $(echo $v6)"

echo
echo "PASS $pass  FAIL $fail   (details: lab/out/results.md, logs: lab/out/)"
{ echo; echo "PASS $pass · FAIL $fail · $(date -u '+%Y-%m-%d %H:%M UTC')"; } >> "$RES"
sed -i '' '1i\
| ID | Result | Check | Evidence |\
|---|---|---|---|
' "$RES" 2>/dev/null || true
