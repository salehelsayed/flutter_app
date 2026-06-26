#!/usr/bin/env bash
# FDC-S1 iOS cold-launch trial runner.
# Terminates the app fully, captures the device syslog (idevicesyslog — picks up
# both the Runner [FLOW] lines and the NSE's NSLog [FLOW] lines), cold-launches
# via devicectl, and saves one log per trial. Needs a PROFILE build installed
# with --dart-define=FDC_FLOW_LOG=1 and the device UNLOCKED.
#
# Usage: fdc_ios_trials.sh <udid> <num_trials> <scenario> <outdir>
# Run in the BACKGROUND (it sleeps between trials).
set -uo pipefail
UDID="${1:?ios udid}"; N="${2:-10}"; SCEN="${3:-warm_cold}"; OUT="${4:?outdir}"
BUNDLE="${FDC_BUNDLE:-com.mknoon.app}"
WINDOW="${FDC_WINDOW:-50}"; SETTLE="${FDC_SETTLE:-4}"
DONE_EVENT="${FDC_DONE_EVENT:-FDC_COLDSTART_FIRST_CIRCUIT_TIMING}"
mkdir -p "$OUT"
echo "[fdc-ios] udid=$UDID trials=$N scenario=$SCEN out=$OUT window=${WINDOW}s done_on=$DONE_EVENT"

for i in $(seq 1 "$N"); do
  ii=$(printf '%02d' "$i")
  LOG="$OUT/${SCEN}_trial_${ii}.log"
  echo "[trial $ii/$N] terminate + cold launch..."
  xcrun devicectl device process terminate --device "$UDID" --bundle-identifier "$BUNDLE" >/dev/null 2>&1 || true
  sleep "$SETTLE"
  idevicesyslog -u "$UDID" > "$LOG" 2>/dev/null &
  LPID=$!
  sleep 1
  xcrun devicectl device process launch --terminate-existing --device "$UDID" "$BUNDLE" >/dev/null 2>&1
  for _s in $(seq 1 "$WINDOW"); do
    if grep -q "$DONE_EVENT" "$LOG" 2>/dev/null; then sleep 2; break; fi
    sleep 1
  done
  kill "$LPID" >/dev/null 2>&1; wait "$LPID" 2>/dev/null || true
  a=$(grep -o 'FDC_COLDSTART_NODE_START_RETURN_TIMING[^}]*sinceProcessStartMs":[0-9-]*' "$LOG" 2>/dev/null | grep -o '[0-9-]*$' | head -1)
  b=$(grep -o 'FDC_COLDSTART_FIRST_CIRCUIT_TIMING[^}]*sinceProcessStartMs":[0-9-]*' "$LOG" 2>/dev/null | grep -o '[0-9-]*$' | head -1)
  nflow=$(grep -c '\[FLOW\]' "$LOG" 2>/dev/null || echo 0)
  echo "[trial $ii] [FLOW] lines=${nflow} | a(node)=${a:-NA}ms b(circuit)=${b:-NA}ms"
done
xcrun devicectl device process terminate --device "$UDID" --bundle-identifier "$BUNDLE" >/dev/null 2>&1 || true
echo "[fdc-ios] done. logs in $OUT"
