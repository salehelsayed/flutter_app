#!/bin/bash
# Android rebuild in the isolated copy: the source that passed run-20260926-185802
# (sync 2026-09-26 00:05Z + fixes up to 362d930e2) + B5 (f150d96d6) + B8 (1ab25c14f, 8a7b8cc54).
# Applies only the commits the copy does not have yet.
# Output: build/beta-android-b8.apk, build/b8_result.txt. The live checkout is not written.
set -u
SRC=/Volumes/CrucialX9/flutter_app
DST=/Volumes/CrucialX9/flutter_app-beta0924
OUT="$SRC/artifacts/beta-20260925/build"
FLUTTER="$HOME/development/flutter-3.47.2/bin/flutter"
RESULT="$OUT/b8_result.txt"; : > "$RESULT"
CALL=android/app/src/main/kotlin/com/mknoon/app/call
cd "$DST" || { echo "NO COPY" >> "$RESULT"; exit 2; }
grep -q "synced_at=2026-09-26T00:05:14Z" .proof-checkout-provenance.txt || { echo "COPY CHANGED" >> "$RESULT"; exit 1; }
apply() {  # apply <label> <patch> <marker file> <marker text>
  if grep -q "$4" "$3"; then echo "$1 ALREADY APPLIED" >> "$RESULT"; return 0; fi
  if git apply --check "$2" >> "$OUT/b8_patch.log" 2>&1 && git apply "$2" >> "$OUT/b8_patch.log" 2>&1; then
    echo "$1 PATCH OK" >> "$RESULT"
  else
    echo "$1 PATCH FAILED (see b8_patch.log)" >> "$RESULT"; cat "$RESULT"; exit 1
  fi
}
: > "$OUT/b8_patch.log"
apply B5 "$SRC/docker-ws/beta/fixes_362d930e2_f150d96d6.patch" "$CALL/MknoonCallAndroidRuntime.kt" MKNOON_TELECOM_REGISTRATION_TIMEOUT_MS
apply B8 "$SRC/docker-ws/beta/fixes_f150d96d6_1ab25c14f.patch" "$CALL/MknoonCallLifecycleController.kt" admitRestoreLocked
apply B8R "$SRC/docker-ws/beta/fixes_1ab25c14f_8a7b8cc54.patch" "$CALL/MknoonCallLifecycleController.kt" dropDeferredAnswer
STAMP=$(date +%y%m%d%H%M%S)
BUILD_NAME="1.0.0-237e88dd5.d266.fix-8a7b8cc54.t${STAMP}"
echo "$BUILD_NAME" > "$OUT/b8_build_name.txt"
DEFINES=$(/usr/bin/python3 -c 'import json,sys
print(" ".join(f"--dart-define={k}={v}" for k, v in json.load(open(sys.argv[1])).items()))' "$SRC/tool/build/voice_call_release_defines.json")
MARK=$(mktemp)
if "$FLUTTER" build apk --debug --target-platform=android-arm64 -t lib/main.dart \
    --dart-define=E2E_TEST_MODE=true --dart-define=PRODUCTION_FCM=true $DEFINES \
    --android-project-arg=enableAndroidNativeCalls=true --build-name="$BUILD_NAME" > "$OUT/android_b8_build.log" 2>&1 \
   && [ build/app/outputs/flutter-apk/app-debug.apk -nt "$MARK" ]; then
  cp build/app/outputs/flutter-apk/app-debug.apk "$OUT/beta-android-b8.apk"; echo "ANDROID OK" >> "$RESULT"
else
  echo "ANDROID FAILED" >> "$RESULT"
fi
echo "$BUILD_NAME" >> "$RESULT"
echo "B8 BUILD DONE" >> "$RESULT"
cat "$RESULT"
