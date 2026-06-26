#!/usr/bin/env bash
# FDC-S0 baseline — Flutter host-gate floor capture (metric 10).
# Runs each gate to completion (does NOT abort on failures), captures full log,
# records exit code. Per-gate wall-clock timeout guards against a device-hang
# (e.g. transport integration tests). Ordered so a stall is isolated last.
set -u
BASE="/Users/I560101/Project-Sat/mknoon-2/flutter_app"
RAW="$BASE/Test-Flight-Improv/Network-Transport-libp2p-Feature/fast-direct-connection/s0-baseline-raw"
cd "$BASE" || exit 99
: > "$RAW/flutter_status.log"
GATES=(baseline 1to1 feed groups transport)
for g in "${GATES[@]}"; do
  echo "=== START gate=$g $(date +%H:%M:%S) ===" >> "$RAW/flutter_status.log"
  timeout 1800 ./scripts/run_test_gates.sh "$g" > "$RAW/flutter_${g}.log" 2>&1
  code=$?
  echo "GATE=$g EXIT=$code $(date +%H:%M:%S)" >> "$RAW/flutter_status.log"
  # Extract the flutter test summary tail for quick read.
  echo "--- tail $g ---" >> "$RAW/flutter_status.log"
  tail -n 6 "$RAW/flutter_${g}.log" >> "$RAW/flutter_status.log" 2>/dev/null
done
echo "=== FLUTTER CHAIN DONE $(date +%H:%M:%S) ===" >> "$RAW/flutter_status.log"
