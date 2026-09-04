#!/bin/bash
# coturn hairpin fix (2026-09-04): with external-ip=13.60.15.36, a peer address
# equal to the public IP is mapped back to the relay address 172.31.34.24, which
# the RFC1918 denied-peer-ip rule then blocks ("A peer IP 172.31.34.24 denied").
# Every relay-only call between two phones died at ICE. allowed-peer-ip is
# checked before denied-peer-ip, so this permits ONLY the relay's own address.
# Runs ON THE BOX via the paramiko helper. Rollback: copy the backup back and
# `sudo systemctl restart coturn`. The conf must stay root:turnserver 0640.
set -u
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
CONF=/etc/turnserver.conf
echo "=== coturn hairpin fix $STAMP ==="
echo "before: $(systemctl is-active coturn) $(ls -l $CONF | awk '{print $1" "$3":"$4}')"
if sudo grep -q '^allowed-peer-ip=172.31.34.24$' $CONF; then echo "already present"; exit 0; fi
sudo cp -p $CONF "$CONF.pre-hairpin-$STAMP" && echo "backup: $CONF.pre-hairpin-$STAMP"
sudo sed -i 's|^# Never relay into loopback, link-local (EC2 metadata), the VPC or private ranges.|# The relay address itself is the one private peer that must be allowed: with\n# external-ip mapping, a phone sending to another phone'"'"'s relayed candidate\n# (public IP) is delivered to 172.31.34.24, and denied-peer-ip below would\n# otherwise block every relay-only call between two phones (2026-09-04).\nallowed-peer-ip=172.31.34.24\n&|' $CONF
sudo chown root:turnserver $CONF && sudo chmod 0640 $CONF
echo "--- diff ---"; sudo diff "$CONF.pre-hairpin-$STAMP" $CONF | sed -E 's/static-auth-secret=.*/static-auth-secret=<masked>/'
echo "perms: $(ls -l $CONF | awk '{print $1" "$3":"$4}')"
sudo grep -cE '^(use-auth-secret|realm=mknoun.xyz|static-auth-secret=.+)$' $CONF | sed 's/^/auth lines present: /'
sudo systemctl restart coturn; sleep 3
echo "after: $(systemctl is-active coturn) NRestarts=$(systemctl show coturn -p NRestarts --value) since $(systemctl show coturn -p ActiveEnterTimestamp --value)"
L=$(sudo ls -t /var/log/turnserver/*.log | head -1); echo "log: $L"
sudo tail -40 "$L" | grep -aE 'realm|auth|WARNING|ERROR|allowed|denied|listener|created' | grep -av 'certificate\|TLS\|private key\|CHANGE_REQUEST' | cut -c1-160 | tail -12
sudo ss -lunp | grep -c ':3478' | sed 's/^/udp 3478 listeners: /'
echo "=== done $(date -u +%Y%m%dT%H%M%SZ) ==="
