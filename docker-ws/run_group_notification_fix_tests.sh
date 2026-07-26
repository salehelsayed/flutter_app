#!/bin/bash
# Test run for the iOS foreground group-notification fix (NSE sidecar discard
# on never-presented foreground pushes). Run ON THE MAC:
#   /Users/I560101/Project-Sat/mknoon-2/flutter_app/docker-ws/run_group_notification_fix_tests.sh
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
RESULT="$RESULT_DIR/group_notification_fix_test_result.txt"
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

if ! TMP="$(mktemp "$RESULT_DIR/.group-notification-result.XXXXXX")"; then
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

echo "1/2 gate + push use-case + identity tests..."
if flutter test \
    test/core/notifications/recent_remote_notification_gate_test.dart \
    test/core/notifications/remote_notification_identity_test.dart \
    test/core/notifications/recent_remote_gate_ios_wiring_test.dart \
    test/features/push/application/handle_foreground_remote_message_use_case_test.dart \
    test/features/push/application/background_message_handler_test.dart \
    2>&1 | tail -5; then
  append_result "notification/push tests: PASS"
else
  overall=FAILED
  append_result "notification/push tests: FAILED"
fi

echo "2/2 strict analyzer..."
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
