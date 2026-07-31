#!/bin/bash
# Read-only: full raw journal (incl. systemd process-exit lines) since the v1.7.1
# install, to identify the crash-loop cause.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
KEY="$REPO/se.pem"
HOST=ubuntu@13.60.15.36
OUT="$REPO/docker-ws/relay_crash_evidence_315_result.txt"

ssh -i "$KEY" -o StrictHostKeyChecking=accept-new "$HOST" '
  echo "=== $(date -u "+%Y-%m-%dT%H:%M:%SZ") ==="
  systemctl show relay-server -p NRestarts -p ActiveState -p SubState
  echo "--- panic/exit/systemd lines since 22:22 ---"
  sudo journalctl -u relay-server --since "2026-07-31 22:22" --no-pager | grep -E "panic|goroutine|fatal|SIGSEGV|signal|Main process|Failed with|exited|Consumed|Scheduled restart|Deactivated|oom|out of memory" | head -40
  echo "--- last 25 lines of the PREVIOUS (dead) instance 644991 ---"
  sudo journalctl -u relay-server --no-pager | grep "relay-server\[644991\]" | tail -25
  echo "--- first 5 + last 15 lines of instance 644974 ---"
  sudo journalctl -u relay-server --no-pager | grep "relay-server\[644974\]" | head -5
  sudo journalctl -u relay-server --no-pager | grep "relay-server\[644974\]" | tail -15
' > "$OUT" 2>&1

echo "wrote $OUT"
