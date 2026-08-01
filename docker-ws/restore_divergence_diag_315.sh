#!/bin/bash
# Read-only diagnosis: which private-data entries diverge between the guard's
# backup tar and the Pixel's CURRENT restored state (member name+size diff).
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO/docker-ws/restore_divergence_diag_315_result.txt"
BK=$(ls -td /var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/mknoon-group-reaction-notification-state-* 2>/dev/null | head -1)

{
  echo "=== $(date -u '+%Y-%m-%dT%H:%M:%SZ') backup=$BK ==="
  TAR="$BK/21071FDF600CSC/private-data.tar"
  [ -f "$TAR" ] || { echo "FATAL: backup tar missing"; exit 0; }
  echo "--- backup member list (name size) -> /tmp lists ---"
  tar -tvf "$TAR" | awk '{print $NF, $5}' | sort > /tmp/backup_members.txt
  wc -l /tmp/backup_members.txt
  echo "--- current device state via run-as (name size) ---"
  adb -s 21071FDF600CSC shell run-as com.mknoon.app find . -type f -exec ls -l {} \; 2>/dev/null \
    | awk '{sz=$5; name=$NF; sub(/^\.\//, "", name); print name, sz}' | sort > /tmp/device_members.txt
  wc -l /tmp/device_members.txt
  echo "--- entries only in BACKUP (missing/changed-name on device) ---"
  comm -23 <(awk '{print $1}' /tmp/backup_members.txt) <(awk '{print $1}' /tmp/device_members.txt) | head -20
  echo "--- entries only on DEVICE (new files since backup) ---"
  comm -13 <(awk '{print $1}' /tmp/backup_members.txt) <(awk '{print $1}' /tmp/device_members.txt) | head -20
  echo "--- same-name size mismatches ---"
  join /tmp/backup_members.txt /tmp/device_members.txt 2>/dev/null | awk '$2 != $3 {print $1, "backup="$2, "device="$3}' | head -20
} > "$OUT" 2>&1

echo "wrote $OUT"
