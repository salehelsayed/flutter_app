#!/bin/bash
# Post-hoc iPhone unified-log pull for call debugging. Usage:
#   collect_iphone_unified_log.sh <UDID> <last-minutes> <start 'YYYY-MM-DD HH:MM:SS'> <end 'YYYY-MM-DD HH:MM:SS'>
# Needs passwordless sudo on the Mac (log collect --device requires root).
# Writes the archive under docker-ws/deploy-captures/unified/<UDID>-<stamp>.logarchive
# and prints Runner-process lines inside [start,end] (local time).
set -uo pipefail
cd "$(dirname "$0")/.."
UDID=$1; MIN=$2; START=$3; END=$4
OUTDIR=docker-ws/deploy-captures/unified; mkdir -p "$OUTDIR"
STAMP=$(date +%y%m%d%H%M%S)
ARCHIVE="$OUTDIR/${UDID:0:8}-$STAMP.logarchive"
if ! sudo -n true 2>/dev/null; then echo "SUDO_UNAVAILABLE"; exit 2; fi
echo "== log collect --device-udid $UDID --last ${MIN}m -> $ARCHIVE"
if ! sudo -n log collect --device-udid "$UDID" --last "${MIN}m" --output "$ARCHIVE" 2>&1; then
  echo "COLLECT_FAILED"; exit 3
fi
sudo -n chown -R "$(id -u):$(id -g)" "$ARCHIVE" 2>/dev/null
echo "== Runner lines $START .. $END"
log show --archive "$ARCHIVE" --start "$START" --end "$END" --style compact \
  --predicate 'process == "Runner" OR eventMessage CONTAINS "com.mknoon.app"' 2>&1 | head -4000
echo "== done"
