#!/bin/bash
# Read-only: provenance for the v1.7.1 deploy — version line count, flags, durability.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
KEY="$REPO/se.pem"
HOST=ubuntu@13.60.15.36
OUT="$REPO/docker-ws/relay_provenance_check_315_result.txt"

ssh -i "$KEY" -o StrictHostKeyChecking=accept-new "$HOST" '
  echo "=== $(date -u "+%Y-%m-%dT%H:%M:%SZ") ==="
  echo "--- start lines since 22:15 UTC (expect exactly one v1.7.1) ---"
  sudo journalctl -u relay-server --since "2026-07-31 22:15" --no-pager | grep -E "Starting relay-server|reaction push enabled|backend=" || true
  echo "--- durability gauge ---"
  curl -s localhost:2112/metrics | grep relay_backend_durable
  echo "--- uptime + restart count ---"
  systemctl show relay-server -p ActiveEnterTimestamp -p NRestarts
  echo "--- push token count ---"
  curl -s localhost:2112/metrics | grep relay_inbox_push_tokens
' > "$OUT" 2>&1

echo "wrote $OUT"
