#!/bin/bash
# Live status of the emulator-5556 proof run (the runner's own stdout is
# buffered by the host bridge until it exits, so read the logs instead).
#   /claude-host-bin/host-run bash docker-ws/proof_5556_status.sh [tail-lines]
set -uo pipefail
DST="${PROOF_DST:-/Volumes/CrucialX9/flutter_app-proof5556}"
N="${1:-8}"
RUNS="$DST/.proof-runs"
[ -d "$RUNS" ] || { echo "no runs yet: $RUNS"; exit 0; }
OUT="$(ls -1d "$RUNS"/* 2>/dev/null | sort | tail -1)"
[ -n "$OUT" ] || { echo "no run directory yet"; exit 0; }
echo "RUNDIR=$OUT"
echo "now=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "=== summary so far ==="
cat "$OUT/summary.txt" 2>/dev/null || echo "(no completed target yet)"
echo "=== per-log tail ($N lines) ==="
for log in "$OUT"/*.log; do
  [ -f "$log" ] || continue
  echo "--- $(basename "$log") ($(wc -l < "$log" | tr -d ' ') lines, modified $(date -r "$log" -u +%H:%M:%SZ)) ---"
  tail -"$N" "$log"
done
echo "=== flutter/gradle processes on this checkout ==="
ps ax -o pid=,etime=,command= 2>/dev/null | grep -i "flutter_app-proof5556" | grep -v grep | head -5
