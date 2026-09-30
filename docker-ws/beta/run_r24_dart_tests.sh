#!/bin/bash
# R2-4 verification: the Dart tests that exercise the changed code, on the live checkout (main + uncommitted
# work), with the pinned Flutter 3.47.2. List: docker-ws/beta/r24_dart_tests.txt.
# Log: build/r24-dart-tests/flutter_test.log (machine log: flutter_test.json); last lines printed at the end.
H="$(cd "$(dirname "$0")" && pwd)"
ROOT=/Volumes/CrucialX9/flutter_app
LOG_DIR="$ROOT/build/r24-dart-tests"; mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/flutter_test.log"
cd "$ROOT" || exit 2
echo "start $(date '+%H:%M:%S')" > "$LOG_DIR/status.txt"
# shellcheck disable=SC2046
bash "$ROOT/docker-ws/flutter_sdk.sh" test --concurrency 4 --reporter expanded \
  --file-reporter "json:$LOG_DIR/flutter_test.json" $(cat "$H/r24_dart_tests.txt") > "$LOG" 2>&1
status=$?
echo "flutter test exit: $status" >> "$LOG_DIR/status.txt"
tail -5 "$LOG" >> "$LOG_DIR/status.txt"
echo "R24 DART TESTS DONE $(date '+%H:%M:%S')" >> "$LOG_DIR/status.txt"
