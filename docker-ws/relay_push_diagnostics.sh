#!/bin/bash
# Pull push-delivery diagnostics from the EC2 relay (mknoun.xyz).
# Written by Claude session 0cb4f030; result lands in docker-ws/relay_push_diagnostics_result.txt
set -u
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
KEY="$REPO_DIR/se.pem"
OUT="$REPO_DIR/docker-ws/relay_push_diagnostics_result.txt"
SSH="ssh -i $KEY -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 ubuntu@13.60.15.36"

{
  echo "=== generated $(date -u '+%Y-%m-%dT%H:%M:%SZ') ==="

  echo; echo "=== relay version + uptime ==="
  $SSH "systemctl status relay-server --no-pager | head -12"

  echo; echo "=== boot lines: version + backend/durability history (30 days) ==="
  $SSH "sudo journalctl -u relay-server --since '30 days ago' --no-pager | grep -E 'Starting relay-server|backend=|durable' | tail -40"

  echo; echo "=== current metrics: durability, push counters, token counts ==="
  $SSH "curl -s localhost:2112/metrics | grep -E 'relay_backend_durable|push_sent|push_token|relay_push' | grep -v '^#'"

  echo; echo "=== push log outcomes last 14 days (counted by type) ==="
  $SSH "sudo journalctl -u relay-server --since '14 days ago' --no-pager | grep -oE '\[PUSH\] (Skip chat push to [^:]+: no registered token|Removed invalid token|Notification sent|Group notification sent|Firebase not initialized|Refusing)' | sed -E 's/(to|for) .*//' | sort | uniq -c | sort -rn"

  echo; echo "=== recent no-token / invalid-token lines (tail 30) ==="
  $SSH "sudo journalctl -u relay-server --since '14 days ago' --no-pager | grep -E 'no registered token|Removed invalid token' | tail -30"

  echo; echo "=== redis push token keys (count + updatedAt spread) ==="
  $SSH "redis-cli --scan --pattern 'relay:push:*' 2>/dev/null | wc -l; redis-cli --scan --pattern 'relay:push:*' 2>/dev/null | head -5"
} > "$OUT" 2>&1

echo "wrote $OUT"
