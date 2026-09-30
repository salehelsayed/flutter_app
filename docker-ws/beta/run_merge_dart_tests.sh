#!/bin/bash
# Runs the Dart tests for the merged beta fixes on the live checkout (main), with the
# pinned Flutter 3.47.2 (docker-ws/flutter_sdk.sh). List: docker-ws/beta/merge_dart_tests.txt.
# Log: build/merge-dart-tests/flutter_test.log; last lines printed at the end.
H="$(cd "$(dirname "$0")" && pwd)"
ROOT=/Volumes/CrucialX9/flutter_app
LOG_DIR="$ROOT/build/merge-dart-tests"; mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/flutter_test.log"
cd "$ROOT" || exit 2
# shellcheck disable=SC2046
bash "$ROOT/docker-ws/flutter_sdk.sh" test --concurrency 4 --reporter failures-only \
  $(cat "$H/merge_dart_tests.txt") > "$LOG" 2>&1
status=$?
echo "flutter test exit: $status"
tail -5 "$LOG"
echo "MERGE DART TESTS DONE"
