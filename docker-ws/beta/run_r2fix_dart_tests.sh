#!/bin/bash
# R2-1 fix validation: the group transition / removal / dissolve Dart tests on the live
# checkout with the pinned Flutter 3.47.2. List: r2fix_dart_tests.txt.
# Log: build/r2fix-dart-tests/flutter_test.log (expanded reporter: every test name + result).
H="$(cd "$(dirname "$0")" && pwd)"
ROOT=/Volumes/CrucialX9/flutter_app
LOG_DIR="$ROOT/build/r2fix-dart-tests"; mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/flutter_test.log"
cd "$ROOT" || exit 2
# shellcheck disable=SC2046
bash "$ROOT/docker-ws/flutter_sdk.sh" test --concurrency 4 --reporter expanded \
  $(cat "$H/r2fix_dart_tests.txt") > "$LOG" 2>&1
status=$?
echo "flutter test exit: $status"
tail -3 "$LOG"
echo "R2FIX DART TESTS DONE"
