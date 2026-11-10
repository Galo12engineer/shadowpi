FROM python:3.12-alpine
COPY whoami.py /whoami.py
# 198.51.100.7 = "a website on the internet". Route back to the hotspot subnet so that a
# leak (client traffic leaving without NAT through the VPN) shows up as 10.0.0.x.
CMD ["sh", "-c", "ip addr add 198.51.100.7/32 dev lo && ip route add 10.0.0.0/24 via 172.30.0.10 && exec python /whoami.py"]
