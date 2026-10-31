#!/bin/bash
# Store release build for build/wt-release-<N>: Android AAB via Flutter (as for 127) and the iOS App Store IPA via
# xcodebuild archive/export with DerivedData + archive on the INTERNAL disk (Xcode builds on CrucialX9 fail since the
# 10-26 Mac restart). Store defines only: no Thoughts/3D switches, update check on, no flow log, production relay default.
#   host-run docker-ws/with_native_lease.py <log> -- bash docker-ws/release_store_build_internal.sh <N>
set -uo pipefail
N=${1:?build number}
REPO=/Volumes/CrucialX9/flutter_app; W="$REPO/build/wt-release-$N"; E="$W/.codex-test-logs/release-$N"; mkdir -p "$E"
DD="$HOME/tmp-dd-store-$N"; ARCH="$DD/Runner.xcarchive"; EXP="$DD/export"
export PATH="$HOME/development/flutter-3.47.2/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" GOTOOLCHAIN=go1.27.1
cd "$W" || exit 2
DEF=tool/build/voice_call_release_defines.json
echo "== provenance $(date -u +%T) head=$(git rev-parse --short HEAD) dirty=$(git status --porcelain | wc -l | tr -d ' ') $(grep -E '^version:' pubspec.yaml)"
python3 scripts/check_update_check_release_defines.py --dart-define-from-file=$DEF || { echo "RELEASE_GUARD FAILED"; exit 3; }
echo "== android $(date -u +%T)"
flutter build appbundle --release --target=lib/main.dart --dart-define-from-file=$DEF \
  --android-project-arg=enableAndroidNativeCalls=true > "$E/android_build.log" 2>&1; echo "android exit=$?"
echo "== ios bindings $(date -u +%T)"
bash scripts/ensure_go_ios_bindings.sh > "$E/ios_bindings.log" 2>&1; echo "bindings exit=$?"
echo "== ios config $(date -u +%T)"
flutter build ios --release --config-only --no-pub --target=lib/main.dart --dart-define-from-file=$DEF \
  --dart-define=PRODUCTION_APNS=true > "$E/ios_config.log" 2>&1; echo "config exit=$?"
rm -rf "$ARCH" "$EXP"
echo "== ios archive $(date -u +%T)"
xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -configuration Release -sdk iphoneos \
  -destination 'generic/platform=iOS' -jobs 1 -allowProvisioningUpdates -derivedDataPath "$DD" \
  -archivePath "$ARCH" archive > "$E/ios_archive.log" 2>&1; echo "archive exit=$?"
echo "== ios export $(date -u +%T)"
xcodebuild -exportArchive -archivePath "$ARCH" -exportOptionsPlist ios/ExportOptions-AppStore.plist \
  -exportPath "$EXP" -allowProvisioningUpdates > "$E/ios_export.log" 2>&1; echo "export exit=$?"
mkdir -p build/ios/ipa; IPA=$(find "$EXP" -maxdepth 1 -name '*.ipa' | head -1)
[ -n "$IPA" ] && cp -p "$IPA" build/ios/ipa/ && rm -rf build/ios/archive && mkdir -p build/ios/archive && cp -R "$ARCH" build/ios/archive/
R="$ARCH/Products/Applications/Runner.app/Runner"
echo "ios_ipa=$(ls build/ios/ipa/*.ipa 2>/dev/null) go_runtime=$(LC_ALL=C grep -a -c 'runtime.main' "$R" 2>/dev/null) nse=$(ls -d "$ARCH/Products/Applications/Runner.app/PlugIns/"*.appex 2>/dev/null | wc -l | tr -d ' ')"
echo "== done $(date -u +%T)"
