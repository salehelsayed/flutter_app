#!/bin/bash
# Run production-shared-xctest (iPhone 11) in the next gap between queue entries; retry if the queue wins the lock.
if [ -z "${XS_DETACHED:-}" ]; then XS_DETACHED=1 nohup bash "$0" >/dev/null 2>&1 & echo "started detached (pid $!)"; exit 0; fi
CFG=/Volumes/CrucialX9/flutter_app/.claude/worktrees/wave3-next/.codex-test-logs/production-bootstrap-migration-20260930/wave4-device-config-ios.json
OUT=/Volumes/CrucialX9/flutter_app/docker-ws/beta/wave5/xctest_slot.out
: > "$OUT"
for i in $(seq 1 2400); do
  if ! pgrep -f "mknoon_checks.py run" >/dev/null; then
    echo "attempt at $(date -u +%T)" >> "$OUT"
    bash /Volumes/CrucialX9/flutter_app/docker-ws/beta/wt_campaign.sh production-shared-xctest "$CFG" > "$OUT.run" 2>&1
    if grep -q "Another Mknoon check run owns" "$OUT.run"; then echo "lost the race; retrying" >> "$OUT"; sleep 1; continue; fi
    grep -E "^(PASS|FAIL|BLOCKED) |^Report" "$OUT.run" >> "$OUT"; echo "end $(date -u +%T)" >> "$OUT"; exit 0
  fi
  sleep 1
done
echo "gave up waiting $(date -u +%T)" >> "$OUT"
