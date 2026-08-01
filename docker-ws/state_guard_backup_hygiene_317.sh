#!/usr/bin/env bash
# Plan 317 E7 retained-backup hygiene (default disposition: archive-nothing-new,
# delete all stale state-guard tmp dirs; durable record = committed diag result
# files + docker-ws/pixel6-state-guard-backup-20260801).
set -u
TMP="/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T"
OUT="docker-ws/state_guard_backup_hygiene_317_result.txt"
{
  echo "=== state_guard_backup_hygiene_317 $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
  echo "--- stale mknoon-*-state-* dirs before ---"
  ls -dt "$TMP"/mknoon-*-state-* 2>/dev/null || echo "(none)"
  echo "--- disposition: DELETE (restores would be destructive; content-perfection proven by diag2/3/6; durable copy pixel6-state-guard-backup-20260801 retained) ---"
  rm -rf "$TMP"/mknoon-*-state-*
  echo "--- after ---"
  ls -dt "$TMP"/mknoon-*-state-* 2>/dev/null || echo "(none)"
} | tee "$OUT"
