#!/bin/bash
# Read-only relay forensics for the 2026-07-31 plan-309 test window.
# Classifies every push decision the relay made in the last 24h so the three
# observed symptoms (iOS reaction silence, media notification failures,
# Android post-background breakage) can be attributed to concrete gates.
# Result lands in docker-ws/relay_push_diagnostics_309_result.txt
set -u
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
KEY="$REPO_DIR/se.pem"
OUT="$REPO_DIR/docker-ws/relay_push_diagnostics_309_result.txt"
SSH="ssh -i $KEY -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 ubuntu@13.60.15.36"

{
  echo "=== generated $(date -u '+%Y-%m-%dT%H:%M:%SZ') ==="

  echo; echo "=== version history today (deploy + rollback provenance) ==="
  $SSH "sudo journalctl -u relay-server --since '2026-07-31 00:00' --no-pager | grep -E 'Starting relay-server|backend=|GROUP_REACTION|DIRECT_REACTION' | head -30"

  echo; echo "=== push counters (cumulative, all labels) ==="
  $SSH "curl -s localhost:2112/metrics | grep -E 'push_sent|push_token' | grep -v '^#'"

  echo; echo "=== last 24h: every PUSH outcome, counted by shape ==="
  $SSH "sudo journalctl -u relay-server --since '24 hours ago' --no-pager | grep '\[PUSH\]' | sed -E 's/^[A-Za-z]+ [0-9]+ [0-9:]+ [^ ]+ [^ ]+ //; s/(to|for) [A-Za-z0-9]{6,}[^ ]*//g; s/group [A-Za-z0-9-]+//g; s/\(attempt [0-9]+\/[0-9]+\)//; s/: .*retrying in.*//' | sort | uniq -c | sort -rn | head -30"

  echo; echo "=== last 24h: PUSH lines per hour (find the test window) ==="
  $SSH "sudo journalctl -u relay-server --since '24 hours ago' --no-pager -o short-iso | grep '\[PUSH\]' | cut -c1-13 | sort | uniq -c"

  echo; echo "=== last 24h: group_reaction + reaction PUSH lines (raw tail 40) ==="
  $SSH "sudo journalctl -u relay-server --since '24 hours ago' --no-pager -o short-iso | grep -iE '\[PUSH\].*(reaction|Refus|invalid|unauthorized|Suppressed)' | tail -40"

  echo; echo "=== last 24h: group store + group push fan-out (tail 40) ==="
  $SSH "sudo journalctl -u relay-server --since '24 hours ago' --no-pager -o short-iso | grep -E '\[GROUP_INBOX\] Stored|\[PUSH\] Group notification sent|\[PUSH\] Skip group push|\[PUSH\] Failed to send group push' | tail -40"

  echo; echo "=== last 24h: 1:1 store + push outcomes (tail 30) ==="
  $SSH "sudo journalctl -u relay-server --since '24 hours ago' --no-pager -o short-iso | grep -E '\[INBOX\] Stored|\[PUSH\] Notification sent|\[PUSH\] Skip chat push|\[PUSH\] Failed to send push|Strict routing fallback|oversized' | tail -30"

  echo; echo "=== last 24h: errors of any kind (tail 20) ==="
  $SSH "sudo journalctl -u relay-server --since '24 hours ago' --no-pager -o short-iso | grep -iE 'error|panic|fatal' | tail -20"
} > "$OUT" 2>&1

echo "wrote $OUT"
