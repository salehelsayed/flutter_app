#!/bin/bash
# Relaunch the mknoon app on the three test phones so a full app start lands in
# the running captures of docker-ws/start_phone_log_captures.sh:
#   iPhones: stop that phone's idevicesyslog, devicectl launch --terminate-existing,
#            then immediately restart idevicesyslog APPENDING to the same file
#            (devicectl operations stall an attached idevicesyslog session).
#   Pixel:   am force-stop + launcher intent; the logcat stream keeps running.
# Usage (Mac or host-run): docker-ws/relaunch_phones_into_captures.sh <CAPTURE_DIR>
set -uo pipefail
cd "$(dirname "$0")/.."
CAP_DIR="${1:?usage: relaunch_phones_into_captures.sh <capture-dir>}"
[ -d "$CAP_DIR" ] || { echo "no capture dir: $CAP_DIR"; exit 1; }
BUNDLE_ID=com.mknoon.app
IPHONE_UDIDS="00008030-001A6D2801BB802E 00008110-00184D622289801E"
PIXEL_SERIAL=21071FDF600CSC
SYSLOG="$(command -v idevicesyslog || echo /opt/homebrew/bin/idevicesyslog)"
if command -v timeout >/dev/null 2>&1; then TO() { timeout "$@"; }; else TO() { shift; "$@"; }; fi
FAILED=0
for UDID in $IPHONE_UDIDS; do
  OUT="$CAP_DIR/iphone_${UDID:0:8}_syslog.txt"
  pkill -f "idevicesyslog -u $UDID" 2>/dev/null; sleep 1
  echo "== iPhone $UDID: relaunch $BUNDLE_ID at $(date -u '+%H:%M:%S')"
  if ! TO 90 xcrun devicectl device process launch --device "$UDID" --terminate-existing "$BUNDLE_ID" >/dev/null 2>&1; then
    echo "$UDID FAILED(launch — is the phone unlocked?)"; FAILED=1
  fi
  nohup "$SYSLOG" -u "$UDID" --process Runner >> "$OUT" 2>&1 &
  echo "   syslog capture restarted pid=$! -> $OUT"
done
if adb devices | awk -v s="$PIXEL_SERIAL" '$1==s && $2=="device" {found=1} END {exit !found}'; then
  echo "== Pixel $PIXEL_SERIAL: relaunch $BUNDLE_ID at $(date -u '+%H:%M:%S')"
  adb -s "$PIXEL_SERIAL" shell am force-stop "$BUNDLE_ID" >/dev/null 2>&1 || true
  adb -s "$PIXEL_SERIAL" shell monkey -p "$BUNDLE_ID" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 \
    || { echo "$PIXEL_SERIAL FAILED(launch)"; FAILED=1; }
else
  echo "Pixel $PIXEL_SERIAL not attached; skipped"
fi
# Wait (bounded) until every capture carries a Dart [FLOW] line from this start.
for i in $(seq 1 30); do
  sleep 2
  ok=1
  for f in "$CAP_DIR"/iphone_*_syslog.txt "$CAP_DIR"/pixel_logcat.txt; do
    [ -f "$f" ] && grep -q '\[FLOW\]' "$f" || ok=0
  done
  [ "$ok" = 1 ] && break
done
echo "--- capture status"
for f in "$CAP_DIR"/*; do
  printf '%s: %s lines, %s [FLOW] lines\n' "$f" "$(wc -l < "$f" | tr -d ' ')" "$(grep -c '\[FLOW\]' "$f" 2>/dev/null || echo 0)"
done
exit $FAILED
