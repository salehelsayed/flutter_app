#!/bin/bash
# Production release iOS device app with Dart flow logging (FDC_FLOW_LOG=1) from the UI-Update worktree with an overridden build number.
#   host-run docker-ws/with_native_lease.py <log> -- bash docker-ws/uiupdate_release_ios_flowlog.sh [build-number]
set -uo pipefail
W=/Volumes/CrucialX9/flutter_app-ui-update
BN="${1:-129}"
cd "$W" || exit 2
VERSION=$(grep -E '^version:' pubspec.yaml | awk '{print $2}')
echo "== provenance $(date -u +%H:%M:%SZ) head=$(git rev-parse HEAD) pubspec=$VERSION build_number=$BN"
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
FW=$(ls "$APP/Frameworks" | tr '\n' ' ')
echo "BRIDGE_SYMS BridgeGenerateIdentity=$SYMS frameworks=$FW"
[ "${SYMS:-0}" -ge 1 ] || { echo "BRIDGE MISSING"; exit 6; }
echo "APP_OK $(date -u +%H:%M:%SZ)"
