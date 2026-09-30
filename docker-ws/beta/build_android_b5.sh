#!/bin/bash
# Android rebuild in the isolated copy AS IT IS (sync 2026-09-26 00:05Z + fixes up to
# 362d930e2, the source that passed run-20260926-185802) plus the B5 commit f150d96d6
# only, so the new APK differs from the tested one by B5 alone.
# Output: build/beta-android-b5.apk, build/b5_result.txt. The live checkout is not written.
set -u
SRC=/Volumes/CrucialX9/flutter_app
DST=/Volumes/CrucialX9/flutter_app-beta0924
OUT="$SRC/artifacts/beta-20260925/build"
PATCH="$SRC/docker-ws/beta/fixes_362d930e2_f150d96d6.patch"
FLUTTER="$HOME/development/flutter-3.47.2/bin/flutter"
RESULT="$OUT/b5_result.txt"; : > "$RESULT"
cd "$DST" || { echo "NO COPY" >> "$RESULT"; exit 2; }
grep -q "synced_at=2026-09-26T00:05:14Z" .proof-checkout-provenance.txt || { echo "COPY CHANGED" >> "$RESULT"; exit 1; }
if grep -q "MKNOON_TELECOM_REGISTRATION_TIMEOUT_MS" android/app/src/main/kotlin/com/mknoon/app/call/MknoonCallAndroidRuntime.kt; then
  echo "B5 ALREADY APPLIED" >> "$RESULT"
elif git apply --check "$PATCH" > "$OUT/b5_patch.log" 2>&1 && git apply "$PATCH" >> "$OUT/b5_patch.log" 2>&1; then
  echo "B5 PATCH OK $(grep -c '^diff --git' "$PATCH") files" >> "$RESULT"
else
  echo "B5 PATCH FAILED (see b5_patch.log)" >> "$RESULT"; cat "$RESULT"; exit 1
fi
STAMP=$(date +%y%m%d%H%M%S)
BUILD_NAME="1.0.0-237e88dd5.d266.fix-f150d96d6.t${STAMP}"
echo "$BUILD_NAME" > "$OUT/b5_build_name.txt"
DEFINES=$(/usr/bin/python3 -c 'import json,sys
print(" ".join(f"--dart-define={k}={v}" for k, v in json.load(open(sys.argv[1])).items()))' "$SRC/tool/build/voice_call_release_defines.json")
MARK=$(mktemp)
if "$FLUTTER" build apk --debug --target-platform=android-arm64 -t lib/main.dart \
    --dart-define=E2E_TEST_MODE=true --dart-define=PRODUCTION_FCM=true $DEFINES \
    --android-project-arg=enableAndroidNativeCalls=true --build-name="$BUILD_NAME" > "$OUT/android_b5_build.log" 2>&1 \
   && [ build/app/outputs/flutter-apk/app-debug.apk -nt "$MARK" ]; then
  cp build/app/outputs/flutter-apk/app-debug.apk "$OUT/beta-android-b5.apk"; echo "ANDROID OK" >> "$RESULT"
else
  echo "ANDROID FAILED" >> "$RESULT"
fi
echo "$BUILD_NAME" >> "$RESULT"
echo "B5 BUILD DONE" >> "$RESULT"
cat "$RESULT"
