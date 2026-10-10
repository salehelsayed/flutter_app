#!/bin/bash
# Runs one Flutter test file with a hard deadline; output streams to a log
# file in docker-ws so the container can read it while the run is live.
# Usage: diag_preflight_tests.sh <test-file> <log-name> [plain-name]
set -u
SDK="${MKNOON_FLUTTER_SDK:-$HOME/development/flutter-3.47.2}"
cd /Volumes/CrucialX9/flutter_app
LOG="docker-ws/$2"
ARGS=(test --no-pub --reporter expanded --timeout 120s "$1")
if [ $# -ge 3 ]; then ARGS+=(--plain-name "$3"); fi
"$SDK/bin/flutter" "${ARGS[@]}" > "$LOG" 2>&1 &
PID=$!
# The deadline timer must not hold the bridge's stdout open after the run.
( sleep 900 && kill "$PID" 2>/dev/null && echo "KILLED_AT_DEADLINE" >> "$LOG" ) \
  </dev/null >/dev/null 2>&1 &
WATCH=$!
wait "$PID"; RC=$?
pkill -P "$WATCH" 2>/dev/null
kill "$WATCH" 2>/dev/null
echo "exit $RC" >> "$LOG"
