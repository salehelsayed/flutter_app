#!/bin/bash
# Release iOS DEVICE build with PRODUCTION config (store defines: no relay override = AWS defaults, update check on,
# no flow log) plus TRANSLATE_PREVIEW=true, for installing a store-identical build over developer-signed installs.
# Swift packages pinned to the tracked Package.resolved. DerivedData on the internal disk.
#   host-run docker-ws/with_native_lease.py <log> -- bash docker-ws/ios_device_build_prod.sh <tree under build/> <evidence dir under repo> <build-number>
set -uo pipefail
REPO=/Volumes/CrucialX9/flutter_app; W="$REPO/build/${1:?tree}"; E="$REPO/${2:?evidence}"; BN="${3:?build-number}"; mkdir -p "$E"
DD="${DD_OVERRIDE:-$HOME/tmp-dd-161}"
export PATH="$HOME/development/flutter-3.47.2/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" GOTOOLCHAIN=go1.27.1
cd "$W" || exit 2
RES1=ios/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved; RES2=ios/Runner.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
VERSION=$(grep -E '^version:' pubspec.yaml | awk '{print $2}')
{
  echo "start $(date -u +%T) head=$(git rev-parse HEAD) dirty=$(git status --porcelain --untracked-files=no | wc -l | tr -d ' ') version=$VERSION build_number=$BN"
  bash scripts/ensure_go_ios_bindings.sh; echo "bindings exit=$?"
  flutter build ios --release --config-only --no-pub --target=lib/main.dart --dart-define=PRODUCTION_APNS=true \
    --dart-define-from-file=tool/build/voice_call_release_defines.json --dart-define=TRANSLATE_PREVIEW=true \
    --build-name="${VERSION%%+*}" --build-number="$BN"; echo "config exit=$?"
  git checkout -- "$RES1" "$RES2"
  xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -configuration Release -sdk iphoneos \
    -destination 'generic/platform=iOS' -jobs 1 -allowProvisioningUpdates -derivedDataPath "$DD" \
    -onlyUsePackageVersionsFromResolvedFile build; echo "build exit=$? $(date -u +%T)"
  echo "resolved_diff=$(git status --porcelain -- "$RES1" "$RES2" | wc -l | tr -d ' ')"
} > "$E/ios_device_build.log" 2>&1
B=$(grep -oE 'build exit=[0-9]+' "$E/ios_device_build.log" | tail -1); echo "$B"; grep -E 'resolved_diff|^start' "$E/ios_device_build.log"
[ "$B" = "build exit=0" ] || { echo "DEVICE BUILD FAILED"; exit 3; }
A=$(find "$DD/Build/Products" -maxdepth 2 -name Runner.app -path '*iphoneos*' | head -1); echo "app=$A"
echo "bundle=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$A/Info.plist") short=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$A/Info.plist") go_runtime=$(LC_ALL=C grep -a -c 'runtime.main' "$A/Runner") nse=$(ls -d "$A/PlugIns/"*.appex 2>/dev/null | wc -l | tr -d ' ')"
APP=$A/Frameworks/App.framework/App
echo "hetzner_relay=$(LC_ALL=C grep -a -c '2-29-62-121.sslip.io' "$APP") aws_relay_host=$(LC_ALL=C grep -a -c 'mknoun.xyz' "$APP")"
