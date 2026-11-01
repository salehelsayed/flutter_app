#!/bin/bash
# Codex-UI native iOS RED for CR-008/IN-008 (Kayan m-fd784028): run the three IosNotificationRecoveryTests on one disposable
# simulator, own DerivedData on the internal disk, unsigned. Logs to the evidence dir, prints the test result lines, then shuts
# the simulator down. Never edits the worktree.
#   host-run docker-ws/with_native_lease.py <log> -- bash docker-ws/codexui_notif_red_test.sh <worktree> <simulator name> <log under repo>
set -uo pipefail
W=${1:?worktree}; NAME=${2:?sim name}; L="/Volumes/CrucialX9/flutter_app/${3:?log}"; mkdir -p "$(dirname "$L")"
SIM=$(xcrun simctl list devices available | grep -E "^ +$NAME \(" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
[ -n "$SIM" ] || { echo "STOP simulator $NAME not found"; exit 3; }
echo "sim=$NAME ${SIM:0:8}"
cd "$W" || exit 2
before=$(git status --porcelain --untracked-files=no | wc -l | tr -d ' ')
xcrun simctl boot "$SIM" 2>/dev/null; xcrun simctl bootstatus "$SIM" -b > /dev/null 2>&1
T=RunnerTests/IosNotificationRecoveryTests
xcodebuild test -workspace ios/Runner.xcworkspace -scheme Runner -destination "platform=iOS Simulator,id=$SIM" \
  -derivedDataPath "$HOME/tmp-dd-codexui-notif" CODE_SIGNING_ALLOWED=NO -parallel-testing-enabled NO \
  -only-testing:$T/testCR008DeliveredContactRequestMatchesOnlyItsPeer \
  -only-testing:$T/testIN008DeliveredIntroductionMatchesOnlyItsCanonicalOffer \
  -only-testing:$T/testTC395ExactGroupInviteRetirementIsSurgicalAndIdempotent > "$L" 2>&1
rc=$?; echo "xcodebuild_exit=$rc" >> "$L"
grep -E "Test Case .*(passed|failed)|error: .*IosNotificationRecoveryTests|Executed [0-9]+ test|\*\* TEST (SUCCEEDED|FAILED)|\*\* BUILD FAILED|error: " "$L" | grep -v "^ld: warning" | head -30
echo "xcodebuild_exit=$rc"
xcrun simctl shutdown "$SIM" 2>/dev/null; echo "sim shutdown: $(xcrun simctl list devices | grep "$SIM" | grep -oE '\((Booted|Shutdown)\)')"
echo "tracked_dirty_before=$before after=$(git status --porcelain --untracked-files=no | wc -l | tr -d ' ')"
