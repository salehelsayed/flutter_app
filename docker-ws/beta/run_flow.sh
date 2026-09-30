#!/bin/bash
# Run one Maestro flow on one device.
# Usage: run_flow.sh <ios|android> <flow.yaml> <label> [KEY=VAL ...]
# Writes <run>/maestro/<label>_<dev>/ (junit, screenshots, maestro logs) and
# prints "FLOW <label> <dev> PASS|FAIL rc=<n>".
. "$(dirname "$0")/beta_env.sh"
RUN=$(current_run)
DEV=$1; FLOW=$2; LABEL=$3; shift 3
if [ "$DEV" = ios ]; then D=$UDID; PEER="$AND_NAME"; ME="$IOS_NAME"; else D=$SERIAL; PEER="$IOS_NAME"; ME="$AND_NAME"; fi
OUTD="$RUN/maestro/${LABEL}_${DEV}"; mkdir -p "$OUTD"
OTHER=android; [ "$DEV" = android ] && OTHER=ios
ENVS=(-e "PEER=$PEER" -e "ME=$ME" -e "DEV=$DEV" -e "OTHER=$OTHER")
for kv in "$@"; do ENVS+=(-e "$kv"); done
start=$(date +%s)
echo "[$(date '+%H:%M:%S')] start $LABEL $DEV" >> "$RUN/timeline.txt"
# The first try skips Maestro's driver reinstall (it is already on the device); the retry below reinstalls it.
REINSTALL=--no-reinstall-driver
run_once() {
  timeout 1200 maestro --device "$D" test $REINSTALL "${ENVS[@]}" \
    --format junit --output "$OUTD/junit.xml" --test-output-dir "$OUTD" \
    "$(dirname "$0")/flows/$FLOW" > "$OUTD/maestro_stdout.txt" 2>&1
}
run_once; rc=$?
# Retry once when Maestro's own device server died or its driver did not start
# (tool fault, not app).
if [ $rc -ne 0 ] && grep -qiE "DeviceServerDiedException|did not start up in time|driver not ready in time|driver.*not (installed|found)|Failed to connect|Unable to launch|XCTest" "$OUTD/junit.xml" "$OUTD/maestro_stdout.txt" 2>/dev/null; then
  echo "[$(date '+%H:%M:%S')] retry $LABEL $DEV (maestro device server/driver failed to start)" >> "$RUN/timeline.txt"
  mv "$OUTD/junit.xml" "$OUTD/junit_attempt1.xml" 2>/dev/null
  cp "$OUTD/maestro_stdout.txt" "$OUTD/maestro_stdout_attempt1.txt"
  sleep 3; REINSTALL=--reinstall-driver; run_once; rc=$?
fi
res=PASS; [ $rc -ne 0 ] && res=FAIL
echo "[$(date '+%H:%M:%S')] end   $LABEL $DEV $res rc=$rc ($(( $(date +%s)-start ))s)" >> "$RUN/timeline.txt"
echo "FLOW $LABEL $DEV $res rc=$rc"
