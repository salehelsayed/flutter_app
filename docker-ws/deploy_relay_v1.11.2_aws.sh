#!/bin/bash
# Remote script (run via relay_ssh.py on the AWS production relay). Owner order 2026-10-26:
# "aws should be the same as Hetzner". Installs the exact Hetzner test-relay binary (v1.11.2,
# sha256 e0b6e8e4..., built from 6bae23448 = main's relay code) after a sha check and a backup.
set -u
WANT=e0b6e8e4ba655ee97b4238278f467c7d5d6786324518d161517336526dba1484
NEW=/tmp/relay-server.v1.11.2
B=/usr/local/bin/relay-server
GOT=$(sha256sum "$NEW" | cut -c1-64)
[ "$GOT" = "$WANT" ] || { echo "ABORT sha mismatch $GOT"; exit 3; }
BK=/usr/local/bin/relay-server.pre-1.11.2-$(date -u +%Y%m%dT%H%M%SZ)
sudo -n cp -p "$B" "$BK" && echo "backup=$BK sha=$(sha256sum "$BK" | cut -c1-16)"
sudo -n install -m0755 "$NEW" "$B" || { echo "ABORT install failed"; exit 4; }
echo "installed sha=$(sha256sum "$B" | cut -c1-64)"
T0=$(date -u '+%Y-%m-%d %H:%M:%S')
sudo -n systemctl restart relay-server
for s in 12 40 40; do
  sleep $s
  echo "t+ $(systemctl show relay-server -p ActiveState -p NRestarts | tr '\n' ' ')"
done
sudo -n journalctl -u relay-server --since "$T0" --no-pager | grep -E 'Starting relay-server v|backend=|durable' | head -5
curl -s localhost:2112/metrics | grep -E '^relay_backend_durable ' || echo "metric relay_backend_durable absent"
rm -f "$NEW"
