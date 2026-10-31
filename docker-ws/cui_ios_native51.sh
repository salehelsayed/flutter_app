#!/bin/bash
# Run the 51 native preservation selectors on the iPhone 11 from the freshly prepared sims iOS bundle.
#   host-run bash docker-ws/cui_ios_native51.sh <evidence-dir-relative-to-worktree>
set -uo pipefail
W=/Volumes/CrucialX9/flutter_app/build/wt-cui-b376
EV="$W/$1"; mkdir -p "$EV"
B="$W/build/sims/prepared/ios.device.production.bundle"
X="$(ls "$B"/TestProducts/*.xctestrun | head -1)"
[ -s "$X" ] || { echo "missing xctestrun" > "$EV/native51.log"; exit 3; }
R="$EV/native51.xcresult"; rm -rf "$R"
{
  echo "start $(date -u +%FT%TZ) xctestrun_sha=$(shasum -a 256 "$X" | cut -c1-16)"
  /usr/bin/xcrun xcodebuild test-without-building -xctestrun "$X" \
    -destination id=00008030-001A6D2801BB802E \
    -parallel-testing-enabled NO -collect-test-diagnostics never \
    -resultBundlePath "$R" \
    -only-testing:RunnerTests/IosNotificationRecoveryTests \
    -only-testing:RunnerTests/ForegroundPushForwardPolicyTests \
    -only-testing:RunnerTests/NotificationResponseDiagnosticTests \
    -only-testing:RunnerTests/NotificationPreviewResolverTests/testNotificationServiceCompletionGateExpiryBeforeResolutionRejectsPublisher \
    -only-testing:RunnerTests/NotificationPreviewResolverTests/testNotificationServiceCompletionGateRejectsStaleRequestGeneration
  rc=$?
  echo "exit=$rc end=$(date -u +%FT%TZ)"
  exit $rc
} > "$EV/native51.log" 2>&1
