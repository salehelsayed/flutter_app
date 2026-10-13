#!/bin/bash
# SE-41: run the update-check XCTests (RunnerTests/UpdateCheckBackgroundTaskTests)
# on an iPhone simulator. Usage: host-run bash docker-ws/se41_xctest.sh [only-testing target, default
# RunnerTests/UpdateCheckBackgroundTaskTests; "RunnerTests" runs the whole bundle]
set -uo pipefail
ONLY="${1:-RunnerTests/UpdateCheckBackgroundTaskTests}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="/opt/homebrew/bin:$PATH"
OUT="$REPO/build/se41-xctest"
rm -rf "$OUT"
mkdir -p "$OUT"
sim="$(xcrun simctl list devices available -j | python3 -c '
import json, sys
d = json.load(sys.stdin)["devices"]
c = sorted((v["name"], v["udid"]) for k, vs in d.items() if "iOS" in k for v in vs if v["name"].startswith("iPhone"))
print(c[-1][1] if c else "")')"
[ -n "$sim" ] || { echo "no iPhone simulator"; exit 2; }
echo "simulator=$sim"
xcrun simctl boot "$sim" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$sim" -b >/dev/null 2>&1
cd "$REPO/ios"
xcodebuild \
  -derivedDataPath "$OUT/derived" \
  -workspace Runner.xcworkspace \
  -scheme Runner \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=$sim" \
  -parallel-testing-enabled NO \
  -resultBundlePath "$OUT/result.xcresult" \
  -only-testing:"$ONLY" \
  CODE_SIGNING_ALLOWED=NO CLANG_ENABLE_EXPLICIT_MODULES=NO \
  test > "$OUT/xcodebuild.log" 2>&1
code=$?
grep -E "error:|Test Case .*failed|Executed|TEST (SUCCEEDED|FAILED)|BUILD FAILED" "$OUT/xcodebuild.log" | tail -60
echo "exit=$code"
