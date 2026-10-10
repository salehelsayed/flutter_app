#!/bin/bash
# Plan 414: run one curated lane in this worktree and keep its log.
# Usage: pdf414_lane.sh <lane> [extra args...]
# Reaps a stray lane of the same name first, so two never run at once.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
LANE="$1"; shift
# Integration tests in the lanes run on the macOS desktop, never on the phones
# (a debug install would replace the phone builds kept for the device proof).
export FLUTTER_DEVICE_ID="${FLUTTER_DEVICE_ID:-macos}"
LOG="$ROOT/Test-Flight-Improv/evidence/414/lane_${LANE}.txt"
pkill -f "$ROOT/scripts/run_test_gates.sh $LANE" 2>/dev/null
sleep 1
if pgrep -f "$ROOT/scripts/run_test_gates.sh $LANE" >/dev/null; then
  echo "refusing: a $LANE lane is still running"
  exit 3
fi
"$ROOT/scripts/run_test_gates.sh" "$LANE" "$@" > "$LOG" 2>&1
CODE=$?
echo "LANE_EXIT=$CODE" >> "$LOG"
tail -25 "$LOG"
