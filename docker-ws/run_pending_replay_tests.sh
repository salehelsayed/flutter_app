#!/bin/bash
# Test run for the invisible-pending-request fix (contact request replay on
# UI attach). Run ON THE MAC:
#   /Users/I560101/Project-Sat/mknoon-2/flutter_app/docker-ws/run_pending_replay_tests.sh
set -uo pipefail
cd "$(dirname "$0")/.."

RESULT=docker-ws/pending_replay_test_result.txt
TMP=$(mktemp)
rm -f "$RESULT"
overall=OK

echo "1/3 contact_request feature tests..."
if flutter test test/features/contact_request/ 2>&1 | tail -5; then
  echo "contact_request feature tests: PASS" >> "$TMP"
else
  overall=FAILED; echo "contact_request feature tests: FAILED" >> "$TMP"
fi

echo "2/3 notification dedupe integration test..."
if flutter test test/integration/contact_request_notification_dedupe_integration_test.dart 2>&1 | tail -3; then
  echo "dedupe integration test: PASS" >> "$TMP"
else
  overall=FAILED; echo "dedupe integration test: FAILED" >> "$TMP"
fi

echo "3/3 analyzer baseline..."
if ./scripts/check_flutter_analyze_baseline.sh 2>&1 | tail -3; then
  echo "analyzer baseline: PASS" >> "$TMP"
else
  overall=FAILED; echo "analyzer baseline: FAILED" >> "$TMP"
fi

echo "$overall" >> "$TMP"
mv "$TMP" "$RESULT"
echo "---"
cat "$RESULT"
