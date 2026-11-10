# Debian bookworm with systemd as PID 1, so the installer's systemctl calls are real.
FROM debian:bookworm
ENV container=docker DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      systemd systemd-sysv dbus sudo iproute2 procps curl ca-certificates openssl \
    && rm -rf /var/lib/apt/lists/* \
    && systemctl mask getty@tty1.service systemd-logind.service
COPY lab-*.sh /usr/local/sbin/
RUN chmod 0755 /usr/local/sbin/lab-*.sh
STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
