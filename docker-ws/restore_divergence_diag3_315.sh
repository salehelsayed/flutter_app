#!/bin/bash
# Read-only v3: CONTENT hash diff — backup tar members vs current device files.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO/docker-ws/restore_divergence_diag3_315_result.txt"
BK=$(ls -td /var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/mknoon-group-reaction-notification-state-* 2>/dev/null | head -1)
WORK=$(mktemp -d)

{
  echo "=== $(date -u '+%Y-%m-%dT%H:%M:%SZ') backup=$BK ==="
  tar -xf "$BK/21071FDF600CSC/private-data.tar" -C "$WORK"
  (cd "$WORK" && find . -type f -exec shasum -a 256 {} \; | sed 's| \./| |' | awk '{print $2, $1}' | sort) > /tmp/backup_hashes.txt
  wc -l /tmp/backup_hashes.txt
  adb -s 21071FDF600CSC shell "run-as com.mknoon.app sh -c 'find . -type f | sed s:^\./:: | while read f; do sha256sum \"\$f\"; done'" \
    | tr -d '\r' | awk '{print $2, $1}' | sed 's|^\./||' | sort > /tmp/device_hashes.txt
  wc -l /tmp/device_hashes.txt
  echo "--- files whose CONTENT diverges (backup vs device) ---"
  join /tmp/backup_hashes.txt /tmp/device_hashes.txt | awk '$2 != $3 {print $1}' | head -30
  echo "--- divergent count ---"
  join /tmp/backup_hashes.txt /tmp/device_hashes.txt | awk '$2 != $3' | wc -l
  rm -rf "$WORK"
} > "$OUT" 2>&1

echo "wrote $OUT"
