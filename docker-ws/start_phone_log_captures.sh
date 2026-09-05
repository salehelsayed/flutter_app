#!/bin/bash
# Start detached log captures for the three test phones and return at once:
#   iPhone 11 + 13 -> idevicesyslog (Runner process; carries Dart [FLOW] lines
#                     when the build has --dart-define=FDC_FLOW_LOG=1)
#   Pixel          -> adb logcat -v threadtime (flutter/[FLOW] lines included)
# Output dir: docker-ws/deploy-captures/fresh-<stamp>/ (printed as CAPTURE_DIR).
# Run on the Mac (or via host-run). Stop with docker-ws/stop_phone_log_captures.sh.
# Landmine: idevicesyslog stalls when devicectl installs/launches on that phone;
# use docker-ws/relaunch_phones_into_captures.sh <dir> to relaunch the apps and
# restart the iPhone captures in one step.
set -uo pipefail
cd "$(dirname "$0")/.."
IPHONE_UDIDS="00008030-001A6D2801BB802E 00008110-00184D622289801E"
PIXEL_SERIAL=21071FDF600CSC
STAMP=$(date +%y%m%d%H%M%S)
CAP_REL="deploy-captures/fresh-$STAMP"
CAP_DIR="docker-ws/$CAP_REL"
mkdir -p "$CAP_DIR"
pkill -f 'idevicesyslog' 2>/dev/null
pkill -f "adb -s $PIXEL_SERIAL logcat" 2>/dev/null
sleep 1
for UDID in $IPHONE_UDIDS; do
  nohup docker-ws/capture_iphone_syslog_any.sh "$UDID" "$CAP_REL/iphone_${UDID:0:8}_syslog.txt" >/dev/null 2>&1 &
  echo "started syslog capture $UDID pid=$! -> $CAP_DIR/iphone_${UDID:0:8}_syslog.txt"
done
if adb devices | awk -v s="$PIXEL_SERIAL" '$1==s && $2=="device" {found=1} END {exit !found}'; then
  adb -s "$PIXEL_SERIAL" logcat -c >/dev/null 2>&1 || true
  nohup adb -s "$PIXEL_SERIAL" logcat -v threadtime > "$CAP_DIR/pixel_logcat.txt" 2>&1 &
  echo "started logcat capture $PIXEL_SERIAL pid=$! -> $CAP_DIR/pixel_logcat.txt"
else
  echo "WARNING: Pixel $PIXEL_SERIAL not attached/authorized; no logcat capture"
fi
sleep 3
pgrep -fl 'idevicesyslog' || echo "WARNING: no idevicesyslog running"
pgrep -fl "adb -s $PIXEL_SERIAL logcat" || echo "WARNING: no logcat capture running"
echo "CAPTURE_DIR=$CAP_DIR"
