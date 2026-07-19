#!/bin/bash
# Follow-up relay push diagnostics: backend switch dating + token store inspection.
set -u
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
KEY="$REPO_DIR/se.pem"
OUT="$REPO_DIR/docker-ws/relay_push_diagnostics2_result.txt"
SSH="ssh -i $KEY -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 ubuntu@13.60.15.36"

{
  echo "=== generated $(date -u '+%Y-%m-%dT%H:%M:%SZ') ==="

  echo; echo "=== env file: backend config lines + file mtime (password masked) ==="
  $SSH "sudo stat -c '%y %n' /etc/mknoon/relay-server.env; sudo grep -E 'RELAY_BACKEND|REDIS' /etc/mknoon/relay-server.env | sed -E 's#(://[^:]*:)[^@]*@#\1***@#'"

  echo; echo "=== journal retention: oldest available entries for relay-server ==="
  $SSH "sudo journalctl -u relay-server --no-pager | head -3; sudo journalctl --list-boots --no-pager 2>/dev/null | head -5"

  echo; echo "=== redis service uptime + key counts via configured URL ==="
  $SSH "sudo systemctl status redis* --no-pager 2>/dev/null | grep -E 'service|Active' | head -4"
  $SSH "URL=\$(sudo grep -E '^REDIS_URL' /etc/mknoon/relay-server.env | cut -d= -f2-); redis-cli -u \"\$URL\" DBSIZE 2>&1; redis-cli -u \"\$URL\" --scan --pattern 'relay:push:*' 2>/dev/null | wc -l"

  echo; echo "=== push token UpdatedAt spread (oldest 5 / newest 5) ==="
  $SSH "URL=\$(sudo grep -E '^REDIS_URL' /etc/mknoon/relay-server.env | cut -d= -f2-); redis-cli -u \"\$URL\" --scan --pattern 'relay:push:*' 2>/dev/null | while read -r k; do redis-cli -u \"\$URL\" GET \"\$k\" 2>/dev/null | python3 -c 'import sys,json;\nimport datetime\ntry:\n e=json.load(sys.stdin); print(e.get(\"UpdatedAt\",\"?\"))\nexcept Exception: pass'; done | sort | sed -n '1,5p;\$p' ; echo '---newest---'; true"

  echo; echo "=== did the Jul-17 skipped chat peer ever register? ==="
  $SSH "sudo journalctl -u relay-server --since '14 days ago' --no-pager | grep -E '12D3KooWM8QzsDJDkcvw' | head -20"

  echo; echo "=== registrations per day (register/token lines) ==="
  $SSH "sudo journalctl -u relay-server --since '14 days ago' --no-pager | grep -iE 'register.*token|token.*register' | grep -viE 'no registered token' | awk '{print \$1, \$2}' | uniq -c | head -20"
} > "$OUT" 2>&1

echo "wrote $OUT"
