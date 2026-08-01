#!/bin/bash
# Read-only v2: member-level diff between guard backup tar and current device
# private data (working run-as invocation, single remote sh -c).
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO/docker-ws/restore_divergence_diag2_315_result.txt"
BK=$(ls -td /var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/mknoon-group-reaction-notification-state-* 2>/dev/null | head -1)

{
  echo "=== $(date -u '+%Y-%m-%dT%H:%M:%SZ') backup=$BK ==="
  TAR="$BK/21071FDF600CSC/private-data.tar"
  tar -tf "$TAR" | sed 's:/$::' | sort > /tmp/backup_names.txt
  wc -l /tmp/backup_names.txt
  adb -s 21071FDF600CSC shell "run-as com.mknoon.app sh -c 'find . -mindepth 1 | sed s:^\./::'" | tr -d '\r' | sort > /tmp/device_names.txt
  wc -l /tmp/device_names.txt
  echo "--- only in BACKUP (device lost/renamed) ---"
  comm -23 /tmp/backup_names.txt /tmp/device_names.txt | head -25
  echo "--- only on DEVICE (new since backup) ---"
  comm -13 /tmp/backup_names.txt /tmp/device_names.txt | head -25
} > "$OUT" 2>&1

echo "wrote $OUT"
