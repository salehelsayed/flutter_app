#!/bin/bash
# Print the failure region of one emulator-5556 proof log, plus its advisory
# triage note if one was written.
#   /claude-host-bin/host-run bash docker-ws/proof_5556_log.sh group_platform [context-lines]
set -uo pipefail
DST="${PROOF_DST:-/Volumes/CrucialX9/flutter_app-proof5556}"
NAME="${1:?usage: proof_5556_log.sh <target-name> [context-lines]}"
CTX="${2:-60}"
RUNS="$DST/.proof-runs"
OUT="$(ls -1d "$RUNS"/* 2>/dev/null | sort | tail -1)"
LOG="$OUT/$NAME.log"
[ -f "$LOG" ] || { echo "no log: $LOG"; exit 2; }
echo "LOG=$LOG ($(wc -l < "$LOG" | tr -d ' ') lines)"

echo "=== first failure marker onward ==="
first="$(grep -n -m 1 -E "Expected:|Actual:|EXCEPTION CAUGHT|TestFailure|Some tests failed|^Failing tests:" "$LOG" | cut -d: -f1)"
if [ -n "${first:-}" ]; then
  start=$(( first - 10 ))
  [ "$start" -lt 1 ] && start=1
  sed -n "${start},$(( start + CTX ))p" "$LOG"
else
  echo "(no failure marker found; tail instead)"
  tail -"$CTX" "$LOG"
fi

echo "=== non-FLOW lines (last $CTX) ==="
grep -v "^\[FLOW\]" "$LOG" | tail -"$CTX"

if [ -f "$LOG.triage.json" ]; then
  echo "=== advisory triage note (not evidence) ==="
  cat "$LOG.triage.json"
fi
