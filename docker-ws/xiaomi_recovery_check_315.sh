#!/bin/bash
# Post-restore health check for the physical Xiaomi + preserve the guard backup durably.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO/docker-ws/xiaomi_recovery_check_315_result.txt"
BACKUP_SRC="/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/mknoon-group-reaction-notification-state-40BlPq"
BACKUP_DST="$REPO/docker-ws/xiaomi-state-guard-backup-20260801"

{
  echo "=== $(date -u '+%Y-%m-%dT%H:%M:%SZ') ==="
  echo "--- preserve guard backup ---"
  if [ -d "$BACKUP_SRC" ]; then
    mkdir -p "$BACKUP_DST"
    cp -R "$BACKUP_SRC/" "$BACKUP_DST/"
    du -sh "$BACKUP_DST"
    ls -la "$BACKUP_DST" | head -8
  else
    echo "guard backup dir GONE: $BACKUP_SRC"
  fi
  echo "--- installed app ---"
  adb -s 21071FDF600CSC shell dumpsys package com.mknoon.app | grep -E "versionName" | head -2
  echo "--- launch app ---"
  adb -s 21071FDF600CSC shell monkey -p com.mknoon.app -c android.intent.category.LAUNCHER 1 2>&1 | tail -2
  sleep 8
  echo "--- app process alive ---"
  adb -s 21071FDF600CSC shell pidof com.mknoon.app || echo "NOT RUNNING"
} > "$OUT" 2>&1

echo "wrote $OUT"
