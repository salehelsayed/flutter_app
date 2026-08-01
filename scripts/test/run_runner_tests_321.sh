#!/usr/bin/env bash
# Plan 321 TC-321-10 gate: run the iOS RunnerTests (XCTest host leg) against an
# available iPhone simulator. The sims-major row native.ios.runner_tests owns
# the automated lane; this is the focused per-plan runner.
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
  -only-testing:"${1:-RunnerTests}" 2>&1 | tail -40
exit "${PIPESTATUS[0]}"
