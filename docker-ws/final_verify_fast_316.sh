#!/bin/bash
# Fast final verification (all journal reads time-bounded).
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
KEY="$REPO/se.pem"
ssh -i "$KEY" -o StrictHostKeyChecking=accept-new ubuntu@13.60.15.36 '
  echo "=== $(date -u "+%Y-%m-%dT%H:%M:%SZ") ==="
  systemctl is-active relay-server; echo "NRestarts=$(systemctl show relay-server -p NRestarts --value)"
  echo "--- android registrations since 23:08Z ---"
  sudo journalctl -u relay-server --since "2026-07-31 23:08" --no-pager | grep -a "Token registered" | grep -a android | tail -3 || echo none
  echo "--- latest STATS ---"
  sudo journalctl -u relay-server --since "-10 minutes" --no-pager | grep -a STATS | tail -1
  echo "--- Refusing oversized since v1.7.2 (must be 0) ---"
  sudo journalctl -u relay-server --since "2026-07-31 23:18" --no-pager | grep -a -c "Refusing oversized" || true
'
