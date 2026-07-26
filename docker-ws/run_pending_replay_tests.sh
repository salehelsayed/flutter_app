#!/bin/bash
# Test run for the invisible-pending-request fix (contact request replay on
# UI attach). Run ON THE MAC:
#   /Users/I560101/Project-Sat/mknoon-2/flutter_app/docker-ws/run_pending_replay_tests.sh
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" || {
  echo "Unable to resolve repository root." >&2
  exit 2
}
cd "$ROOT_DIR" || {
  echo "Unable to enter repository root: $ROOT_DIR" >&2
  exit 2
}

RESULT_DIR="$ROOT_DIR/docker-ws"
RESULT="$RESULT_DIR/pending_replay_test_result.txt"
[[ -d "$RESULT_DIR" ]] || {
  echo "Result directory does not exist: $RESULT_DIR" >&2
  exit 2
}

TMP=
cleanup() {
  cleanup_status=$?
  trap - EXIT
  if [[ -n "$TMP" && ( -e "$TMP" || -L "$TMP" ) ]]; then
    if ! rm -f -- "$TMP"; then
      echo "Unable to remove result staging file: $TMP" >&2
      exit 2
    fi
  fi
  exit "$cleanup_status"
}
trap cleanup EXIT

if ! TMP="$(mktemp "$RESULT_DIR/.pending-replay-result.XXXXXX")"; then
  echo "Unable to create result staging file in $RESULT_DIR." >&2
  exit 2
fi
if [[ -z "$TMP" || ! -f "$TMP" ]]; then
  echo "Result staging file was not created." >&2
  exit 2
fi
if [[ -e "$RESULT" || -L "$RESULT" ]]; then
  if ! rm -f -- "$RESULT"; then
    echo "Unable to remove prior result: $RESULT" >&2
    exit 2
  fi
fi

append_result() {
  if ! printf '%s\n' "$1" >>"$TMP"; then
    echo "Unable to write staged result: $TMP" >&2
    exit 2
  fi
}

overall=OK

echo "1/3 contact_request feature tests..."
if flutter test test/features/contact_request/ 2>&1 | tail -5; then
  append_result "contact_request feature tests: PASS"
else
  overall=FAILED
  append_result "contact_request feature tests: FAILED"
fi

echo "2/3 notification dedupe integration test..."
if flutter test test/integration/contact_request_notification_dedupe_integration_test.dart 2>&1 | tail -3; then
  append_result "dedupe integration test: PASS"
else
  overall=FAILED
  append_result "dedupe integration test: FAILED"
fi

echo "3/3 strict analyzer..."
if ./scripts/check_flutter_analyze_strict.sh 2>&1 | tail -3; then
  append_result "strict analyzer: PASS"
else
  overall=FAILED
  append_result "strict analyzer: FAILED"
fi

append_result "$overall"
if ! mv -f -- "$TMP" "$RESULT"; then
  echo "Unable to persist result atomically: $RESULT" >&2
  exit 2
fi
TMP=

if ! printf '%s\n' "---"; then
  echo "Unable to print result separator." >&2
  exit 2
fi
if ! cat -- "$RESULT"; then
  echo "Unable to print persisted result: $RESULT" >&2
  exit 2
fi

if [[ "$overall" == "FAILED" ]]; then
  exit 1
fi
exit 0
