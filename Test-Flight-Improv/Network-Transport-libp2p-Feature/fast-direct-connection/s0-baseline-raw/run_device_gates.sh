#!/usr/bin/env bash
# FDC-S0 baseline — device-gated host floor (transport + baseline integration files).
# These integration_test/* files need a booted simulator (not headless host).
# Bounded per-gate timeout guards against a real-network/peer hang (MEMORY: sim stalls).
set -u
BASE="/Users/I560101/Project-Sat/mknoon-2/flutter_app"
RAW="$BASE/Test-Flight-Improv/Network-Transport-libp2p-Feature/fast-direct-connection/s0-baseline-raw"
cd "$BASE" || exit 99
export FLUTTER_DEVICE_ID="1B098DFF-6294-407A-A209-BBF360893485"   # iPhone 16e (booted)
: > "$RAW/device_status.log"
echo "device=$FLUTTER_DEVICE_ID" >> "$RAW/device_status.log"
for g in transport baseline; do
  echo "=== START gate=$g $(date +%H:%M:%S) ===" >> "$RAW/device_status.log"
  timeout 900 ./scripts/run_test_gates.sh "$g" > "$RAW/device_${g}.log" 2>&1
  code=$?
  echo "GATE=$g EXIT=$code $(date +%H:%M:%S)" >> "$RAW/device_status.log"
  echo "--- summary lines $g ---" >> "$RAW/device_status.log"
  grep -aE '(\+[0-9]+ ?(-[0-9]+)?: ?(All tests passed|Some tests failed)|All tests passed!|Some tests failed|No devices|Connection refused|timed out|TimeoutException)' "$RAW/device_${g}.log" 2>/dev/null | tail -8 >> "$RAW/device_status.log"
done
echo "=== DEVICE CHAIN DONE $(date +%H:%M:%S) ===" >> "$RAW/device_status.log"
