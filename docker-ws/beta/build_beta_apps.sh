#!/bin/bash
# Builds the beta-test apps from the CURRENT working tree:
#   Android debug APK (arm64, Pixel 7a emulator) and iOS simulator debug app.
# Debug + E2E_TEST_MODE is required for friend seeding (intro_e2e_config.json).
# Release voice-call flags; production relay (default addresses); FCM on.
set -u
cd /Volumes/CrucialX9/flutter_app
FLUTTER="$HOME/development/flutter-3.47.2/bin/flutter"
OUT=artifacts/beta-20260924/build
mkdir -p "$OUT"
STAMP=$(date +%y%m%d%H%M%S)
SHA=$(git rev-parse --short HEAD)
DIRTY=$(git status --porcelain | wc -l | tr -d ' ')
BUILD_NAME="1.0.0-${SHA}.d${DIRTY}.t${STAMP}"
echo "$BUILD_NAME" > "$OUT/build_name.txt"
DEFINES=(--dart-define-from-file=tool/build/voice_call_release_defines.json
  --dart-define=E2E_TEST_MODE=true --dart-define=PRODUCTION_FCM=true)
MARK=$(mktemp)
RESULT="$OUT/result.txt"; : > "$RESULT"

echo "=== android build $BUILD_NAME"
if "$FLUTTER" build apk --debug --target-platform=android-arm64 -t lib/main.dart \
    "${DEFINES[@]}" --android-project-arg=enableAndroidNativeCalls=true \
    --build-name="$BUILD_NAME" > "$OUT/android_build.log" 2>&1; then
  APK=build/app/outputs/flutter-apk/app-debug.apk
  if [ "$APK" -nt "$MARK" ]; then cp "$APK" "$OUT/beta-android.apk"; echo "ANDROID OK $BUILD_NAME" >> "$RESULT"
  else echo "ANDROID FAILED stale-artifact" >> "$RESULT"; fi
else echo "ANDROID FAILED build (see android_build.log)" >> "$RESULT"; fi

echo "=== ios simulator build"
if "$FLUTTER" build ios --simulator --debug -t lib/main.dart "${DEFINES[@]}" \
    --build-name="$BUILD_NAME" --build-number="$STAMP" > "$OUT/ios_build.log" 2>&1; then
  APP=build/ios/iphonesimulator/Runner.app
  if [ "$APP/Info.plist" -nt "$MARK" ] || [ "$APP" -nt "$MARK" ]; then
    rm -rf "$OUT/Runner.app"; cp -R "$APP" "$OUT/Runner.app"; echo "IOS OK $BUILD_NAME" >> "$RESULT"
  else echo "IOS FAILED stale-artifact" >> "$RESULT"; fi
else echo "IOS FAILED build (see ios_build.log)" >> "$RESULT"; fi
cat "$RESULT"
