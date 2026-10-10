#!/bin/bash
# Checks the merged tree before main is pushed: pub get, full analyze, and
# the test folders touched by both sides of the merge.
set -u
SDK="${MKNOON_FLUTTER_SDK:-$HOME/development/flutter-3.47.2}"
cd /Volumes/CrucialX9/flutter_app
LOG=docker-ws/merge_check_20261010.log
: > "$LOG"
"$SDK/bin/flutter" pub get >> "$LOG" 2>&1; echo "pub exit $?" >> "$LOG"
"$SDK/bin/dart" analyze lib test >> "$LOG" 2>&1; echo "analyze exit $?" >> "$LOG"
"$SDK/bin/flutter" test --no-pub --concurrency 4 --reporter failures-only --timeout 180s \
  test/features/conversation test/features/call test/core/bootstrap >> "$LOG" 2>&1 &
PID=$!
( sleep 2700 && kill "$PID" 2>/dev/null && echo "KILLED_AT_DEADLINE" >> "$LOG" ) </dev/null >/dev/null 2>&1 &
WATCH=$!
wait "$PID"; RC=$?
pkill -P "$WATCH" 2>/dev/null; kill "$WATCH" 2>/dev/null
echo "flutter test exit $RC" >> "$LOG"
echo "ALL_DONE" >> "$LOG"
