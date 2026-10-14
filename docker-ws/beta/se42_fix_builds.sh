#!/bin/bash
# SE-42 device-finding fixes (2026-10-14): builds the live working tree and
# installs it over the existing identities (no uninstall).
#   Android: debug + native calls on, release voice-call defines -> Pixel 6 + emulator-5554
#   iOS:     profile + release voice-call defines (+ FDC_FLOW_LOG=1 when IOS_FLOW_LOG=1) -> iPhone 13
# Serial on purpose. Output: artifacts/se42-fix-20261014/result.txt
set -u
cd "$(dirname "$0")/../.." || exit 2
. docker-ws/_flutter_sdk_env.sh
OUT=artifacts/se42-fix-20261014
mkdir -p "$OUT"
RESULT="$OUT/result.txt"; echo "---- run $(date)" >> "$RESULT"
note() { echo "[$(date '+%H:%M:%S')] $*" >> "$RESULT"; }
PIXEL=21071FDF600CSC
EMU=emulator-5554
IPHONE13=93B4C4D0-F4B7-50F6-B130-0A7578BA4E9E
DEFINES=tool/build/voice_call_release_defines.json
note "head=$(git rev-parse --short HEAD) dirty=$(git status --porcelain | wc -l | tr -d ' ')"

if [ "${SKIP_ANDROID:-0}" != 1 ]; then
  note "android build start"
  flutter build apk --debug --no-pub --dart-define-from-file=$DEFINES \
    --android-project-arg=enableAndroidNativeCalls=true > "$OUT/android-build.log" 2>&1 \
    || { note "ANDROID BUILD FAILED"; exit 1; }
  APK=build/app/outputs/flutter-apk/app-debug.apk
  note "android built sha256=$(shasum -a 256 $APK | cut -d' ' -f1)"
  for d in $PIXEL $EMU; do
    adb -s $d install -r -t $APK > "$OUT/install-$d.log" 2>&1 \
      && note "installed $d" || note "INSTALL FAILED $d"
  done
fi

if [ "${SKIP_IOS:-0}" != 1 ]; then
  note "ios build start"
  scripts/ensure_go_ios_bindings.sh > "$OUT/ios-go.log" 2>&1 || { note "IOS GO BINDINGS FAILED"; exit 1; }
  flutter build ios --profile --no-pub --dart-define-from-file=$DEFINES \
    ${IOS_FLOW_LOG:+--dart-define=FDC_FLOW_LOG=1} > "$OUT/ios-build.log" 2>&1 \
    || { note "IOS BUILD FAILED"; exit 1; }
  APP=build/ios/iphoneos/Runner.app
  note "ios built runner sha256=$(shasum -a 256 $APP/Runner | cut -d' ' -f1)"
  xcrun devicectl device install app --device $IPHONE13 "$PWD/$APP" > "$OUT/ios-install.log" 2>&1 \
    && note "installed iphone13" || note "IOS INSTALL FAILED"
fi
note "DONE"
