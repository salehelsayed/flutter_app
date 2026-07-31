#!/bin/bash
# Read-only: confirm v1.7.1 stability minutes after deploy + first peer/QUIC evidence.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
KEY="$REPO/se.pem"
HOST=ubuntu@13.60.15.36
OUT="$REPO/docker-ws/relay_stability_confirm_315_result.txt"

ssh -i "$KEY" -o StrictHostKeyChecking=accept-new "$HOST" '
  echo "=== $(date -u "+%Y-%m-%dT%H:%M:%SZ") ==="
  systemctl is-active relay-server
  systemctl show relay-server -p NRestarts -p ActiveEnterTimestamp
  echo "--- panics since deploy (must be 0) ---"
  sudo journalctl -u relay-server --since "2026-07-31 22:30" --no-pager | grep -c panic || true
  echo "--- peer connections + stats since deploy ---"
  sudo journalctl -u relay-server --since "2026-07-31 22:30" --no-pager | grep -E "Peer connected|STATS|Token registered" | tail -8 || true
  echo "--- push token gauge ---"
  curl -s localhost:2112/metrics | grep -E "relay_inbox_push_tokens|relay_backend_durable" | grep -v "^#"
' > "$OUT" 2>&1

echo "wrote $OUT"
