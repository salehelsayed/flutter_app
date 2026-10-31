#!/bin/bash
# Run the iOS call lifecycle/store/bridge/diagnostic RunnerTests selection for build/wt-iosrecovery on an iPhone simulator.
#   host-run bash docker-ws/iosrecovery_xctest.sh   (under the native lease)
set -uo pipefail
W=/Volumes/CrucialX9/flutter_app/build/wt-iosrecovery
export PATH="/opt/homebrew/bin:$PATH"
OUT="$W/.codex-test-logs/iosrecovery/xctest"
rm -rf "$OUT"; mkdir -p "$OUT"
sim="$(xcrun simctl list devices available -j | python3 -c '
import json, sys
d = json.load(sys.stdin)["devices"]
c = sorted((v["name"], v["udid"]) for k, vs in d.items() if "iOS" in k for v in vs if v["name"] == "iPhone 17 Pro")
print(c[-1][1] if c else "")')"
[ -n "$sim" ] || { echo "no iPhone 17 Pro simulator"; exit 2; }
echo "simulator=iPhone 17 Pro start=$(date -u +%FT%TZ)"
xcrun simctl boot "$sim" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$sim" -b >/dev/null 2>&1
cd "$W/ios"
xcodebuild \
  -derivedDataPath "$OUT/derived" \
  -workspace Runner.xcworkspace -scheme Runner -configuration Debug \
  -destination "platform=iOS Simulator,id=$sim" \
  -parallel-testing-enabled NO -collect-test-diagnostics never \
  -resultBundlePath "$OUT/result.xcresult" \
  -only-testing:RunnerTests/MknoonCallKitLifecycleTests \
  -only-testing:RunnerTests/PendingNativeCallStoreTests \
  -only-testing:RunnerTests/MknoonCallNativeBridgeTests \
  -only-testing:RunnerTests/MknoonCallDiagnosticSpoolTests \
  -only-testing:RunnerTests/MknoonVoipPushRegistryTests \
  -only-testing:RunnerTests/VoipPayloadParserTests \
  -only-testing:RunnerTests/IosCallConfigurationTests \
  -only-testing:RunnerTests/OpaqueCallContactResolverTests \
  CODE_SIGNING_ALLOWED=NO CLANG_ENABLE_EXPLICIT_MODULES=NO \
  test > "$OUT/xcodebuild.log" 2>&1
code=$?
grep -E "error:|Test Case .*failed|Executed [0-9]+ test|TEST (SUCCEEDED|FAILED)|BUILD FAILED" "$OUT/xcodebuild.log" | tail -40
for t in testFreshStartupRetiresAbsentAdoptedRingingAndConnectedJournals testFreshStartupPreservesCallKitLiveAdoptedJournal testOrphanReconciliationWaitsForDurableTerminalAndReceipt testOrphanReceiptKeepsSuccessorAudioAndLiveUUIDCannotBeAcknowledged; do
  grep -E "Test Case .*$t.* (passed|failed)" "$OUT/xcodebuild.log" | tail -1 | sed -E 's/.*(passed|failed).*/'"$t"' \1/'
done
xcrun simctl shutdown "$sim" >/dev/null 2>&1 || true
echo "exit=$code end=$(date -u +%FT%TZ)"
exit $code
