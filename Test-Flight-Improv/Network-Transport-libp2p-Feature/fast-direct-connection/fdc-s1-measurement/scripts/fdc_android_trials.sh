#!/usr/bin/env bash
# FDC-S1 Android cold-launch trial runner.
# Force-quits the app fully, clears logcat, cold-launches, and captures one log
# file per trial until the first-circuit event (or a window timeout). Realistic
# cold-start timing requires a PROFILE build (AOT) installed with
# --dart-define=FDC_FLOW_LOG=1 so [FLOW] events reach logcat.
#
# Usage: fdc_android_trials.sh <udid> <num_trials> <scenario> <outdir>
#   scenario: warm_cold | notif_tap | mdns | network
# Run this in the BACKGROUND (it sleeps between trials).
set -uo pipefail
UDID="${1:?adb udid}"; N="${2:-10}"; SCEN="${3:-warm_cold}"; OUT="${4:?outdir}"
PKG="${FDC_PKG:-com.mknoon.app}"
ACT="${FDC_ACT:-com.mknoon.app/.MainActivity}"
WINDOW="${FDC_WINDOW:-45}"          # max seconds to capture per trial
SETTLE="${FDC_SETTLE:-4}"           # seconds the process must stay dead (true cold)
DONE_EVENT="${FDC_DONE_EVENT:-FDC_COLDSTART_FIRST_CIRCUIT_TIMING}"
mkdir -p "$OUT"
echo "[fdc] udid=$UDID trials=$N scenario=$SCEN out=$OUT window=${WINDOW}s done_on=$DONE_EVENT"

for i in $(seq 1 "$N"); do
  ii=$(printf '%02d' "$i")
  LOG="$OUT/${SCEN}_trial_${ii}.log"
  echo "[trial $ii/$N] force-stop + cold launch..."
  adb -s "$UDID" shell am force-stop "$PKG" >/dev/null 2>&1
  sleep "$SETTLE"
  adb -s "$UDID" logcat -c >/dev/null 2>&1 || true
  adb -s "$UDID" logcat -v time > "$LOG" 2>/dev/null &
  LPID=$!
  # true cold OS launch (not `flutter run`); -W waits for the activity to be up.
  adb -s "$UDID" shell am start -W -n "$ACT" >/dev/null 2>&1
  for _s in $(seq 1 "$WINDOW"); do
    if grep -q "$DONE_EVENT" "$LOG" 2>/dev/null; then
      sleep 2     # let trailing events flush
      break
    fi
    sleep 1
  done
  kill "$LPID" >/dev/null 2>&1; wait "$LPID" 2>/dev/null || true
  n_fdc=$(grep -c 'FDC_COLDSTART\|node:startup_timing\|circuit_address:timing' "$LOG" 2>/dev/null || echo 0)
  a=$(grep -o 'FDC_COLDSTART_NODE_START_RETURN_TIMING[^}]*sinceProcessStartMs":[0-9-]*' "$LOG" 2>/dev/null | grep -o '[0-9-]*$' | head -1)
  b=$(grep -o 'FDC_COLDSTART_FIRST_CIRCUIT_TIMING[^}]*sinceProcessStartMs":[0-9-]*' "$LOG" 2>/dev/null | grep -o '[0-9-]*$' | head -1)
  echo "[trial $ii] captured ${n_fdc} timing lines | a(node)=${a:-NA}ms b(circuit)=${b:-NA}ms"
done

adb -s "$UDID" shell am force-stop "$PKG" >/dev/null 2>&1
echo "[fdc] done. logs in $OUT"
