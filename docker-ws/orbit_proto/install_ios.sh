#!/bin/bash
# Builds the standalone Orbit depth prototype (prototypes/orbit_depth/main.dart)
# and installs it IN PLACE over com.mknoon.app on one iPhone (app data kept).
# Restoring the real app afterwards = a normal in-place deploy of lib/main.dart.
# Usage (on the Mac, via host-run): install_ios.sh [UDID]
set -uo pipefail
cd "$(dirname "$0")/../.."
UDID="${1:-00008110-00184D622289801E}"
OUT=docker-ws/orbit_proto
RESULT="$OUT/install_ios_result.txt"
: > "$RESULT"
note() { echo "$*" | tee -a "$RESULT"; }
SDK="${MKNOON_FLUTTER_SDK:-$HOME/development/flutter-3.47.2}"
FLUTTER="$SDK/bin/flutter"
[ -x "$FLUTTER" ] || FLUTTER=flutter
RUN_STAMP=$(date +%y%m%d%H%M%S)
APP=build/ios/iphoneos/Runner.app
note "repo=$(pwd) udid=$UDID stamp=$RUN_STAMP"

# This checkout has no GoMknoon.xcframework, so pod install drops the Go pods
# from ios/Podfile.lock, and Xcode rewrites info.plist. The prototype needs
# neither; put both tracked files back after the build.
mkdir -p "$OUT/tracked_backup"
cp ios/Podfile.lock "$OUT/tracked_backup/Podfile.lock"
cp info.plist "$OUT/tracked_backup/info.plist"
restore_tracked() {
  cp "$OUT/tracked_backup/Podfile.lock" ios/Podfile.lock
  cp "$OUT/tracked_backup/info.plist" info.plist
}
trap restore_tracked EXIT

if ! "$FLUTTER" build ios --release --target=prototypes/orbit_depth/main.dart \
    --build-name=1.0.0-orbitproto --build-number="$RUN_STAMP" \
    > "$OUT/build_ios.log" 2>&1 || [ ! -d "$APP" ]; then
  note "FAILED(build) — tail of $OUT/build_ios.log:"
  tail -40 "$OUT/build_ios.log" | tee -a "$RESULT"
  exit 1
fi
if [ ! "$APP/Runner" -nt "$RESULT" ]; then
  note "FAILED(stale-artifact)"; exit 1
fi

# Flutter.framework/Info.plist can break the code seal on this volume;
# re-sign framework then app when verification fails.
if ! xcrun codesign --verify --deep --strict "$APP" >/dev/null 2>&1; then
  ID="Apple Development: Saleh Elsayed (QGRWQ86DP5)"
  note "seal broken — re-signing"
  xcrun codesign --force --preserve-metadata=identifier,entitlements,flags --sign "$ID" "$APP/Frameworks/Flutter.framework" >> "$RESULT" 2>&1
  xcrun codesign --force --preserve-metadata=identifier,entitlements,flags --sign "$ID" "$APP" >> "$RESULT" 2>&1
  if ! xcrun codesign --verify --deep --strict "$APP" >> "$RESULT" 2>&1; then
    note "FAILED(codesign)"; exit 1
  fi
fi

if ! xcrun devicectl device install app --device "$UDID" "$APP" > "$OUT/install_ios.log" 2>&1; then
  note "FAILED(install) — tail of $OUT/install_ios.log:"
  tail -20 "$OUT/install_ios.log" | tee -a "$RESULT"
  exit 1
fi
xcrun devicectl device process launch --device "$UDID" --terminate-existing com.mknoon.app >> "$OUT/install_ios.log" 2>&1 \
  || note "WARN(launch failed — unlock the phone and open Mknoon)"
GOT=$(xcrun devicectl device info apps --device "$UDID" --bundle-id com.mknoon.app 2>/dev/null | awk '/com.mknoon.app/ {print $NF}')
if [ "$GOT" = "$RUN_STAMP" ]; then
  note "OK prototype installed bundleVersion=$RUN_STAMP (verified)"
else
  note "FAILED(verify: installed '$GOT' != built '$RUN_STAMP')"; exit 1
fi
