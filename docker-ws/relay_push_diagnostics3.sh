#!/bin/bash
# Correlate "no registered token" push skips with relay restarts over the full journal window.
set -u
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
KEY="$REPO_DIR/se.pem"
OUT="$REPO_DIR/docker-ws/relay_push_diagnostics3_result.txt"
SSH="ssh -i $KEY -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 ubuntu@13.60.15.36"

{
  echo "=== generated $(date -u '+%Y-%m-%dT%H:%M:%SZ') ==="

  echo; echo "=== relay-server process starts per day (systemd Started/Starting lines) ==="
  $SSH "sudo journalctl -u relay-server --no-pager | grep -E 'Starting relay-server v|Started relay-server|Starting mknoon relay' | awk '{print \$1, \$2}' | uniq -c"

  echo; echo "=== 'no registered token' CHAT push skips per day (full retention) ==="
  $SSH "sudo journalctl -u relay-server --no-pager | grep 'Skip chat push' | awk '{print \$1, \$2}' | uniq -c"

  echo; echo "=== chat pushes SENT per day (full retention) ==="
  $SSH "sudo journalctl -u relay-server --no-pager | grep -E '\[PUSH\] Notification sent' | awk '{print \$1, \$2}' | uniq -c"

  echo; echo "=== [REDIS] lines before Jul 12 (was redis active earlier?) ==="
  $SSH "sudo journalctl -u relay-server --until '2026-07-12 00:00:00' --no-pager | grep -c '\[REDIS\]' || true"
} > "$OUT" 2>&1

echo "wrote $OUT"
