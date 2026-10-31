#!/bin/bash
# 129 store build: the 128 store recipe run in build/wt-translate-129 after store129_setup.sh (local +129 bump commit):
# Play AAB + iOS App Store archive and export to IPA (no upload). Internal-disk DerivedData. TRANSLATE_PREVIEW=true.
# Swift packages pinned with -onlyUsePackageVersionsFromResolvedFile (resolve + archive); Package.resolved hashed after every step.
# Records the local App Store profile state before and after the export (read-only probe).
#   bash docker-ws/store129_build.sh <evidence dir under repo>
set -uo pipefail
REPO=/Volumes/CrucialX9/flutter_app; W="$REPO/build/wt-translate-129"; E="$REPO/${1:?evidence}"; mkdir -p "$E"
DD="$HOME/tmp-dd-store-129"; ARCH="$DD/Runner.xcarchive"; EXP="$DD/export"
export PATH="$HOME/development/flutter-3.47.2/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" GOTOOLCHAIN=go1.27.1
cd "$W" || exit 2
DEF=tool/build/voice_call_release_defines.json
TP="--dart-define=TRANSLATE_PREVIEW=true"
RES1=ios/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved; RES2=ios/Runner.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
res() { echo "resolved_$1 $(shasum -a 256 $RES1 | cut -c1-16) $(shasum -a 256 $RES2 | cut -c1-16) git_diff=$(git status --porcelain -- $RES1 $RES2 | wc -l | tr -d " ")"; }
res start
echo "== provenance $(date -u +%T) head=$(git rev-parse --short HEAD) dirty=$(git status --porcelain | wc -l | tr -d ' ') $(grep -E '^version:' pubspec.yaml)"
[ -f android/key.properties ] || { echo "NO key.properties"; exit 4; }
python3 scripts/check_update_check_release_defines.py --dart-define-from-file=$DEF || { echo "RELEASE_GUARD FAILED"; exit 3; }
bash "$REPO/docker-ws/translate_main_profile_probe.sh" > "$E/profiles_before.txt" 2>&1
echo "== android $(date -u +%T)"
rm -f build/app/outputs/bundle/release/app-release.aab
flutter build appbundle --release --target=lib/main.dart --dart-define-from-file=$DEF \
  $TP --android-project-arg=enableAndroidNativeCalls=true > "$E/android_build.log" 2>&1; echo "android exit=$?"
echo "== ios bindings $(date -u +%T)"
bash scripts/ensure_go_ios_bindings.sh > "$E/ios_bindings.log" 2>&1; echo "bindings exit=$?"
echo "== ios config $(date -u +%T)"
flutter build ios --release --config-only --no-pub --target=lib/main.dart --dart-define-from-file=$DEF \
  --dart-define=PRODUCTION_APNS=true $TP > "$E/ios_config.log" 2>&1; echo "config exit=$?"; res after_config
if [ "$(git status --porcelain -- $RES1 $RES2 | wc -l | tr -d " ")" != "0" ]; then echo "flutter config re-resolved packages: restoring tracked Package.resolved before the pinned resolve"; git checkout -- $RES1 $RES2; res restored; fi
echo "== ios resolve (pinned) $(date -u +%T)"
xcodebuild -resolvePackageDependencies -workspace ios/Runner.xcworkspace -scheme Runner -derivedDataPath "$DD" -onlyUsePackageVersionsFromResolvedFile > "$E/ios_resolve.log" 2>&1; echo "resolve exit=$?"; res after_resolve
rm -rf "$ARCH" "$EXP"
echo "== ios archive $(date -u +%T)"
xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -configuration Release -sdk iphoneos \
  -destination 'generic/platform=iOS' -jobs 1 -allowProvisioningUpdates -derivedDataPath "$DD" \
  -archivePath "$ARCH" -onlyUsePackageVersionsFromResolvedFile archive > "$E/ios_archive.log" 2>&1; echo "archive exit=$?"; res after_archive
echo "== ios export $(date -u +%T)"
xcodebuild -exportArchive -archivePath "$ARCH" -exportOptionsPlist ios/ExportOptions-AppStore.plist \
  -exportPath "$EXP" -allowProvisioningUpdates > "$E/ios_export.log" 2>&1; echo "export exit=$?"
bash "$REPO/docker-ws/translate_main_profile_probe.sh" > "$E/profiles_after.txt" 2>&1; res after_export
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
