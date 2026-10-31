#!/bin/bash
# Signed debug iOS simulator build of a worktree with FDC_FLOW_LOG=1 (call under with_native_lease.py).
#   host-run docker-ws/with_native_lease.py <log> -- bash docker-ws/build_ios_sim_debug_wt.sh <worktree>
set -uo pipefail
W="${1:?worktree}"; cd "$W" || exit 2
export PATH="$HOME/development/flutter-3.47.2/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" GOTOOLCHAIN=go1.27.1
echo "start $(date -u +%T) head=$(git rev-parse HEAD) dirty=$(git status --porcelain | wc -l | tr -d ' ')"
bash scripts/ensure_go_ios_bindings.sh; echo "bindings exit=$?"
flutter build ios --simulator --debug --no-pub --dart-define-from-file=tool/build/voice_call_release_defines.json --dart-define=FDC_FLOW_LOG=1; rc=$?
echo "build exit=$rc $(date -u +%T)"
A=build/ios/iphonesimulator/Runner.app
ls -d "$A" && /usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$A/Info.plist"
codesign -d --entitlements - "$A" 2>&1 | grep -c application-groups
nm -gU "$A/Frameworks/GoMknoon.framework/GoMknoon" 2>/dev/null | grep -c Mobile || find "$A" -maxdepth 3 -name 'GoMknoon*' | head -3
exit $rc
