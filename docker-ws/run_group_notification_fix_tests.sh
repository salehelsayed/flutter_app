#!/bin/bash
# Test run for the iOS foreground group-notification fix (NSE sidecar discard
# on never-presented foreground pushes). Run ON THE MAC:
#   /Users/I560101/Project-Sat/mknoon-2/flutter_app/docker-ws/run_group_notification_fix_tests.sh
set -uo pipefail
cd "$(dirname "$0")/.."

RESULT=docker-ws/group_notification_fix_test_result.txt
TMP=$(mktemp)
rm -f "$RESULT"
overall=OK

echo "1/2 gate + push use-case + identity tests..."
if flutter test \
    test/core/notifications/recent_remote_notification_gate_test.dart \
    test/core/notifications/remote_notification_identity_test.dart \
    test/core/notifications/recent_remote_gate_ios_wiring_test.dart \
    test/features/push/application/handle_foreground_remote_message_use_case_test.dart \
    test/features/push/application/background_message_handler_test.dart \
    2>&1 | tail -5; then
  echo "notification/push tests: PASS" >> "$TMP"
else
  overall=FAILED; echo "notification/push tests: FAILED" >> "$TMP"
fi

echo "2/2 analyzer baseline..."
export ANALYZER_BASELINE_LOG_PATH=docker-ws/flutter_analyze_log.txt
if ./scripts/check_flutter_analyze_baseline.sh 2>&1 | tail -3; then
  echo "analyzer baseline: PASS" >> "$TMP"
else
  overall=FAILED; echo "analyzer baseline: FAILED" >> "$TMP"
fi

echo "$overall" >> "$TMP"
mv "$TMP" "$RESULT"
echo "---"
cat "$RESULT"
