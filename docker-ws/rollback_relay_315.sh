#!/bin/bash
# ROLLBACK: reinstall the pre-plan315 backup (v1.6.0) and verify stability.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
KEY="$REPO/se.pem"
HOST=ubuntu@13.60.15.36
OUT="$REPO/docker-ws/rollback_relay_315_result.txt"

ssh -i "$KEY" -o StrictHostKeyChecking=accept-new "$HOST" '
  set -e
  BACKUP=$(ls -t /usr/local/bin/relay-server.pre-plan315-* | head -1)
  echo "restoring: $BACKUP"
  sudo install -m0755 "$BACKUP" /usr/local/bin/relay-server
  sudo systemctl restart relay-server
  sleep 10
  echo "--- state after 10s ---"
  systemctl is-active relay-server
  systemctl show relay-server -p NRestarts -p ActiveEnterTimestamp
  sudo journalctl -u relay-server --since "-30 seconds" --no-pager | grep -E "Starting relay-server|backend=" | tail -4
  sleep 20
  echo "--- state after 30s (must still be the same PID / no new start) ---"
  systemctl is-active relay-server
  systemctl show relay-server -p NRestarts
  sudo journalctl -u relay-server --since "-15 seconds" --no-pager | tail -5
' > "$OUT" 2>&1

echo "wrote $OUT"
