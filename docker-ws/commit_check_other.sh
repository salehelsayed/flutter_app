#!/bin/bash
# Pre-commit check for the remaining uncommitted app work (call runtime,
# app diagnostics, Orbit): full analyze, the affected test folders, and the
# app diagnostics Swift type-check.
set -u
SDK="${MKNOON_FLUTTER_SDK:-$HOME/development/flutter-3.47.2}"
cd /Volumes/CrucialX9/flutter_app
LOG=docker-ws/commit_check_other.log
: > "$LOG"
echo "=== analyze ===" >> "$LOG"
"$SDK/bin/dart" analyze lib test >> "$LOG" 2>&1
echo "analyze exit $?" >> "$LOG"
echo "=== swift typecheck ===" >> "$LOG"
bash docker-ws/typecheck_app_diagnostics_swift.sh >> "$LOG" 2>&1
echo "swift exit $?" >> "$LOG"
echo "=== flutter test ===" >> "$LOG"
"$SDK/bin/flutter" test --no-pub --concurrency 4 --reporter failures-only --timeout 180s \
  test/features/call test/core/diagnostics test/core/bootstrap test/features/orbit \
  test/features/feed/presentation/screens/feed_wired_test.dart >> "$LOG" 2>&1 &
PID=$!
( sleep 2400 && kill "$PID" 2>/dev/null && echo "KILLED_AT_DEADLINE" >> "$LOG" ) </dev/null >/dev/null 2>&1 &
WATCH=$!
wait "$PID"; RC=$?
pkill -P "$WATCH" 2>/dev/null; kill "$WATCH" 2>/dev/null
echo "flutter test exit $RC" >> "$LOG"
echo "ALL_DONE" >> "$LOG"
