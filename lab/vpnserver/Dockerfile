FROM debian:bookworm
RUN apt-get update && apt-get install -y --no-install-recommends openvpn easy-rsa iptables iproute2 \
    && rm -rf /var/lib/apt/lists/*
COPY entrypoint.sh /entrypoint.sh
CMD ["bash", "/entrypoint.sh"]
