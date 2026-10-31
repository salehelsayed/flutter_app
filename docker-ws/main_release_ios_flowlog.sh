#!/bin/bash
# Production release iOS device app with Dart flow logging (FDC_FLOW_LOG=1) from a given worktree, with an overridden build number.
#   host-run docker-ws/with_native_lease.py <log> -- bash docker-ws/main_release_ios_flowlog.sh <worktree> <build-number>
set -uo pipefail
W="${1:?worktree}"; BN="${2:?build-number}"
cd "$W" || exit 2
. docker-ws/_flutter_sdk_env.sh
VERSION=$(grep -E '^version:' pubspec.yaml | awk '{print $2}')
echo "== provenance $(date -u +%H:%M:%SZ) head=$(git rev-parse HEAD) dirty=$(git status --porcelain | wc -l | tr -d ' ') pubspec=$VERSION build_number=$BN"
python3 scripts/check_update_check_release_defines.py \
  --dart-define-from-file=tool/build/voice_call_release_defines.json || { echo "RELEASE_GUARD FAILED"; exit 3; }
echo "== ensure_go_ios_bindings $(date -u +%H:%M:%SZ)"
bash scripts/ensure_go_ios_bindings.sh || { echo "GO_IOS_BINDINGS FAILED"; exit 4; }
MARK=$(mktemp)
APP=build/ios/iphoneos/Runner.app
echo "== flutter build ios $(date -u +%H:%M:%SZ)"
flutter build ios --release --target=lib/main.dart --dart-define=PRODUCTION_APNS=true --dart-define=FDC_FLOW_LOG=1 \
  --dart-define-from-file=tool/build/voice_call_release_defines.json \
  --build-name="${VERSION%%+*}" --build-number="$BN"
rc=$?
if [ $rc -ne 0 ]; then echo "BUILD FAILED rc=$rc"; exit $rc; fi
[ "$APP/Runner" -nt "$MARK" ] || { echo "STALE APP"; exit 5; }
echo "BUNDLE version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Info.plist") build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Info.plist")"
SYMS=$(grep -c BridgeGenerateIdentity "$APP/Runner" 2>/dev/null || true)
echo "BRIDGE_SYMS BridgeGenerateIdentity=$SYMS frameworks=$(ls "$APP/Frameworks" | tr '\n' ' ')"
[ "${SYMS:-0}" -ge 1 ] || { echo "BRIDGE MISSING"; exit 6; }
echo "APP_OK $(date -u +%H:%M:%SZ)"
