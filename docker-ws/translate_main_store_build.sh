#!/bin/bash
# Translate gate: the 128 store recipe (docker-ws/release_store_build_internal.sh) run in build/wt-translate-main
# with no version bump: Play AAB + iOS App Store archive and export to IPA (no upload). Internal-disk DerivedData.
# Records the local App Store profile state before and after the export (read-only probe).
#   bash docker-ws/translate_main_store_build.sh <evidence dir under repo>
set -uo pipefail
REPO=/Volumes/CrucialX9/flutter_app; W="$REPO/build/wt-translate-main"; E="$REPO/${1:?evidence}"; mkdir -p "$E"
DD="$HOME/tmp-dd-store-translate"; ARCH="$DD/Runner.xcarchive"; EXP="$DD/export"
export PATH="$HOME/development/flutter-3.47.2/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" GOTOOLCHAIN=go1.27.1
cd "$W" || exit 2
DEF=tool/build/voice_call_release_defines.json
echo "== provenance $(date -u +%T) head=$(git rev-parse --short HEAD) dirty=$(git status --porcelain | wc -l | tr -d ' ') $(grep -E '^version:' pubspec.yaml)"
[ -f android/key.properties ] || { echo "NO key.properties"; exit 4; }
python3 scripts/check_update_check_release_defines.py --dart-define-from-file=$DEF || { echo "RELEASE_GUARD FAILED"; exit 3; }
bash "$REPO/docker-ws/translate_main_profile_probe.sh" > "$E/profiles_before.txt" 2>&1
echo "== android $(date -u +%T)"
rm -f build/app/outputs/bundle/release/app-release.aab
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
bash "$REPO/docker-ws/translate_main_profile_probe.sh" > "$E/profiles_after.txt" 2>&1
mkdir -p build/ios/ipa; rm -f build/ios/ipa/*.ipa; IPA=$(find "$EXP" -maxdepth 1 -name '*.ipa' | head -1)
[ -n "$IPA" ] && cp -p "$IPA" build/ios/ipa/ && rm -rf build/ios/archive && mkdir -p build/ios/archive && cp -R "$ARCH" build/ios/archive/
R="$ARCH/Products/Applications/Runner.app/Runner"
echo "ios_ipa=$(ls build/ios/ipa/*.ipa 2>/dev/null) go_runtime=$(LC_ALL=C grep -a -c 'runtime.main' "$R" 2>/dev/null) nse=$(ls -d "$ARCH/Products/Applications/Runner.app/PlugIns/"*.appex 2>/dev/null | wc -l | tr -d ' ')"
A=build/app/outputs/bundle/release/app-release.aab
[ -f "$A" ] && echo "aab=$W/$A sha256=$(shasum -a 256 "$A" | cut -c1-64) bytes=$(stat -f %z "$A")"
for I in build/ios/ipa/*.ipa; do [ -f "$I" ] || continue
  echo "ipa=$W/$I sha256=$(shasum -a 256 "$I" | cut -c1-64) bytes=$(stat -f %z "$I")"
  T=$(mktemp -d); unzip -q "$I" -d "$T"; P=$(ls -d "$T"/Payload/*.app | head -1)
  echo "ipa CFBundleVersion=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$P/Info.plist") short=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$P/Info.plist")"
  codesign -d --entitlements :- "$P" 2>/dev/null | tr '<' '\n<' | grep -E 'increased-memory|aps-environment|beta-reports|get-task' -A1 | tr -d '\n'; echo
  security cms -D -i "$P/embedded.mobileprovision" 2>/dev/null > "$T/p.plist"; echo "embedded_profile=$(/usr/libexec/PlistBuddy -c 'Print :Name' "$T/p.plist") created=$(/usr/libexec/PlistBuddy -c 'Print :CreationDate' "$T/p.plist")"
  codesign -dvv "$P" 2>&1 | grep -E 'Authority=' | head -2
  rm -rf "$T"; done
echo "== done $(date -u +%T)"
