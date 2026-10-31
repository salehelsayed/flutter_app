#!/bin/bash
# Production release APK from the UI-Update worktree with an overridden build number.
#   host-run docker-ws/with_native_lease.py <log> -- bash docker-ws/uiupdate_release_apk.sh [build-number]
set -uo pipefail
W=/Volumes/CrucialX9/flutter_app-ui-update
BN="${1:-127}"
cd "$W" || exit 2
VERSION=$(grep -E '^version:' pubspec.yaml | awk '{print $2}')
echo "== provenance $(date -u +%H:%M:%SZ) head=$(git rev-parse HEAD) pubspec=$VERSION build_number=$BN"
python3 scripts/check_update_check_release_defines.py \
  --dart-define-from-file=tool/build/voice_call_release_defines.json || { echo "RELEASE_GUARD FAILED"; exit 3; }
echo "== ensure_go_android_bindings $(date -u +%H:%M:%SZ)"
bash scripts/ensure_go_android_bindings.sh || { echo "GO_ANDROID_BINDINGS FAILED"; exit 4; }
MARK=$(mktemp)
APK=build/app/outputs/flutter-apk/app-release.apk
echo "== flutter build apk $(date -u +%H:%M:%SZ)"
flutter build apk --release --target=lib/main.dart \
  --build-name="${VERSION%%+*}" --build-number="$BN" \
  --dart-define-from-file=tool/build/voice_call_release_defines.json \
  --android-project-arg=enableAndroidNativeCalls=true
rc=$?
if [ $rc -ne 0 ]; then echo "BUILD FAILED rc=$rc"; exit $rc; fi
if [ ! "$APK" -nt "$MARK" ]; then echo "STALE APK"; exit 5; fi
echo "APK $W/$APK sha256=$(shasum -a 256 "$APK" | cut -d' ' -f1) size=$(du -m "$APK" | cut -f1)MB"
echo "== done $(date -u +%H:%M:%SZ)"
