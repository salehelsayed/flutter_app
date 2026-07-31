#!/bin/bash
# Final combined verification: Xiaomi peer health post-restore + v1.7.2 steady state.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
KEY="$REPO/se.pem"
HOST=ubuntu@13.60.15.36
OUT="$REPO/docker-ws/final_verify_315_316_result.txt"

ssh -i "$KEY" -o StrictHostKeyChecking=accept-new "$HOST" '
  echo "=== $(date -u "+%Y-%m-%dT%H:%M:%SZ") ==="
  systemctl is-active relay-server; systemctl show relay-server -p NRestarts --value
  echo "--- android token registrations since the Xiaomi relaunch (23:08Z) ---"
  sudo journalctl -u relay-server --since "2026-07-31 23:08" --no-pager | grep -a "Token registered" | grep -a android | tail -4 || echo none
  echo "--- current STATS ---"
  sudo journalctl -u relay-server --no-pager | grep -a STATS | tail -1
  echo "--- wake counters (post-restart process; zero until next reaction) ---"
  curl -s localhost:2112/metrics | grep -a relay_group_reaction_wake | grep -v "^#" || echo "none yet this process"
  echo "--- TC-08 steady: Refusing oversized since v1.7.2 (must be 0) ---"
  sudo journalctl -u relay-server --since "2026-07-31 23:18" --no-pager | grep -a -c "Refusing oversized" || true
' > "$OUT" 2>&1

echo "wrote $OUT"
