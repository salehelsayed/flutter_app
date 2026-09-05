#!/usr/bin/env bash
# Same lane as run_runner_tests_321.sh, but keeps every assertion failure line
# instead of the last 40 lines of xcodebuild output. Usage:
#   scripts/test/run_runner_tests_failures.sh RunnerTests/SomeTests[/testCase]
set -uo pipefail
cd "$(dirname "$0")/../.."

SIM_ID=$(xcrun simctl list devices available | grep -E 'iPhone' | head -1 | grep -oE '[0-9A-F-]{36}')
if [ -z "$SIM_ID" ]; then
  echo "NO_AVAILABLE_IPHONE_SIMULATOR"
  exit 2
fi
echo "simulator: $SIM_ID"

xcodebuild test \
  -workspace ios/Runner.xcworkspace \
  -scheme Runner \
  -destination "platform=iOS Simulator,id=$SIM_ID" \
  CODE_SIGNING_ALLOWED=NO \
  -parallel-testing-enabled NO \
  -only-testing:"${1:-RunnerTests}" 2>&1 \
  | grep -E 'error:|Test Case .* (passed|failed)|Executed [0-9]+ tests|TEST (FAILED|SUCCEEDED)|BUILD FAILED' \
  | sed 's#/Volumes/CrucialX9/flutter_app/##'
exit "${PIPESTATUS[0]}"
