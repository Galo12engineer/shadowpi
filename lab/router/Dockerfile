# Debian bookworm with systemd as PID 1, so the installer's systemctl calls are real.
FROM debian:bookworm
ENV container=docker DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      systemd systemd-sysv dbus sudo iproute2 procps curl ca-certificates openssl \
    && rm -rf /var/lib/apt/lists/* \
    && systemctl mask getty@tty1.service systemd-logind.service \
    && rm -f /usr/sbin/policy-rc.d
# policy-rc.d: the debian Docker image ships one that exits 101, which forbids apt to start
# services after installing them. A real Debian / Raspberry Pi OS has no such file, so there
# apt starts php-fpm, dnsmasq, tor... right away. Removed to make the lab behave like the
# real system; with it in place the lab reported a "panel 502 after install" (I3) that a
# real install does not have.
COPY lab-*.sh /usr/local/sbin/
RUN chmod 0755 /usr/local/sbin/lab-*.sh
STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
