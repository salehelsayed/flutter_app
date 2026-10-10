#!/bin/bash
# Pre-commit check for the call preflight diagnostics change: analyze the
# changed Dart files, then run their test files one at a time.
set -u
SDK="${MKNOON_FLUTTER_SDK:-$HOME/development/flutter-3.47.2}"
cd /Volumes/CrucialX9/flutter_app
LOG=docker-ws/commit_check_diag.log
: > "$LOG"
echo "=== analyze ===" >> "$LOG"
"$SDK/bin/dart" analyze lib/app/bootstrap/call_signaling_composition.dart lib/app/bootstrap/call_wake_contact_key_backfill.dart lib/app/bootstrap/production_call_signaling_graph.dart lib/features/call/application/outgoing_call_capability.dart lib/features/call/diagnostics/call_diagnostic_schema.dart lib/features/conversation/presentation/screens/conversation_wired.dart test/core/bootstrap/call_signaling_composition_test.dart test/core/bootstrap/call_wake_contact_key_backfill_test.dart test/features/conversation/presentation/screens/conversation_wired_test.dart >> "$LOG" 2>&1
echo "analyze exit $?" >> "$LOG"
for t in test/features/call/diagnostics/call_diagnostics_test.dart test/core/bootstrap/call_signaling_composition_test.dart test/core/bootstrap/call_wake_contact_key_backfill_test.dart test/features/conversation/presentation/screens/conversation_wired_test.dart; do
  echo "=== $t ===" >> "$LOG"
  "$SDK/bin/flutter" test --no-pub --reporter failures-only --timeout 120s "$t" >> "$LOG" 2>&1 &
  PID=$!
  ( sleep 1200 && kill "$PID" 2>/dev/null && echo "KILLED_AT_DEADLINE" >> "$LOG" ) </dev/null >/dev/null 2>&1 &
  WATCH=$!
  wait "$PID"; RC=$?
  pkill -P "$WATCH" 2>/dev/null; kill "$WATCH" 2>/dev/null
  echo "exit $RC $t" >> "$LOG"
done
echo "ALL_DONE" >> "$LOG"
