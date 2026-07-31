#!/bin/bash
# Read-only: full relay service status + raw journal tail after the v1.7.1 restart.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
KEY="$REPO/se.pem"
HOST=ubuntu@13.60.15.36
OUT="$REPO/docker-ws/relay_health_check_315_result.txt"

ssh -i "$KEY" -o StrictHostKeyChecking=accept-new "$HOST" '
  echo "=== $(date -u "+%Y-%m-%dT%H:%M:%SZ") ==="
  systemctl is-active relay-server || true
  echo "--- systemctl status ---"
  systemctl status relay-server --no-pager -l | head -25 || true
  echo "--- raw journal tail 60 ---"
  sudo journalctl -u relay-server -n 60 --no-pager | tail -60
' > "$OUT" 2>&1

echo "wrote $OUT"
