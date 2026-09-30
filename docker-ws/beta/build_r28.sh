#!/bin/bash
# R2-6 follow-up 3 validation build (2026-09-28). Syncs the live working tree into the isolated copy, then builds the
# Android debug APK only (the iPhone is the caller and keeps build d505; the fix is Android native + callee Dart),
# runs the Kotlin call unit tests and the Dart call UI tests in the copy. Same settings as round 1: debug +
# E2E_TEST_MODE, release voice-call defines, PRODUCTION_FCM, production relay. The live checkout is only read.
# Output: artifacts/beta-20260928/build-r2-8/{result.txt,...}
set -u
SRC=/Volumes/CrucialX9/flutter_app
DST=/Volumes/CrucialX9/flutter_app-beta0924
OUT="$SRC/artifacts/beta-20260928/build-r2-8"
FLUTTER="$HOME/development/flutter-3.47.2/bin/flutter"
NEW_GO=closeUnresponsiveRelayConn   # Go symbol added by cbb13e8f5: proves the binding is current
mkdir -p "$OUT"
RESULT="$OUT/result.txt"; : > "$RESULT"
note() { echo "[$(date '+%H:%M:%S')] $*" >> "$RESULT"; }

note "sync start"
PROOF_DST="$DST" PROOF_MAX_GB=8 bash "$SRC/docker-ws/prepare_proof_checkout_5556.sh" > "$OUT/prepare.log" 2>&1 \
  || { note "PREPARE FAILED (see prepare.log)"; exit 1; }
cd "$DST" || { note "NO COPY"; exit 2; }
cp .proof-checkout-provenance.txt "$OUT/provenance.txt"
note "synced: $(tr '\n' ' ' < .proof-checkout-provenance.txt)"
CALL=android/app/src/main/kotlin/com/mknoon/app/call
for m in "$CALL/MknoonCallLifecycleController.kt:fun updatePresentationAndRefreshIncoming" \
         "$CALL/MknoonCallNativeBridge.kt:controller.updatePresentationAndRefreshIncoming" \
         "$CALL/MknoonCallNativeBridge.kt:updatePresentation accepted=" \
         "$CALL/MknoonCallNotificationFactory.kt:callerName(nativeCallId)" \
         "lib/features/call/presentation/foreground_call_overlay.dart:_nameLoaded ? _contactDisplayName"; do
  grep -qF "${m#*:}" "${m%%:*}" || { note "R2-6 MARKER MISSING ${m#*:}"; exit 1; }
done
for m in "lib/features/call/application/handle_incoming_call_signal.dart:CALL_INCOMING_SIGNAL_NOT_ACCEPTED" \
         "$CALL/MknoonCallAndroidRuntime.kt:MKNOON_TELECOM_REGISTRATION_TIMEOUT_MS" \
         "lib/core/media/audio_recorder_service.dart:prepareForCall" \
         "lib/features/call/presentation/locked_call_projection.dart:await publish(_avatar)" \
         "third_party/video_compress/android/src/main/kotlin/com/example/video_compress/VideoCompressPlugin.kt:safeFrameRate"; do
  grep -qF "${m#*:}" "${m%%:*}" || note "warning: earlier fix marker missing: ${m#*:}"
done
note "R2-6 fix markers present"

STAMP=$(date +%y%m%d%H%M%S)
SHA=$(sed -n 's/^source_head_short=//p' .proof-checkout-provenance.txt)
DIRTY=$(sed -n 's/^source_dirty_files=//p' .proof-checkout-provenance.txt)
BUILD_NAME="1.0.0-${SHA}.d${DIRTY}.t${STAMP}"
echo "$BUILD_NAME" > "$OUT/build_name.txt"
defines() {
  echo --dart-define=E2E_TEST_MODE=true --dart-define=PRODUCTION_FCM=true
  /usr/bin/python3 -c 'import json,sys
for k,v in json.load(open(sys.argv[1])).items(): print(f"--dart-define={k}={v}")' "$SRC/tool/build/voice_call_release_defines.json"
}
defines > "$OUT/defines_android.txt"

note "android build $BUILD_NAME"
M=$(mktemp)
if "$FLUTTER" build apk --debug --target-platform=android-arm64 -t lib/main.dart $(defines) \
    --android-project-arg=enableAndroidNativeCalls=true --build-name="$BUILD_NAME" > "$OUT/android_build.log" 2>&1 \
   && [ build/app/outputs/flutter-apk/app-debug.apk -nt "$M" ]; then
  cp build/app/outputs/flutter-apk/app-debug.apk "$OUT/beta-android.apk"
  T=$(mktemp -d); unzip -qo "$OUT/beta-android.apk" 'lib/arm64-v8a/*' -d "$T" 2>/dev/null
  n=$(cat "$T"/lib/arm64-v8a/*.so 2>/dev/null | LC_ALL=C grep -a -c "$NEW_GO"); rm -rf "$T"
  note "ANDROID OK go_new_symbol=$n"
else
  note "ANDROID FAILED (see android_build.log)"
fi

if grep -q "ANDROID OK" "$RESULT"; then
  n=$(unzip -p "$OUT/beta-android.apk" 'classes*.dex' 2>/dev/null | LC_ALL=C grep -a -c "updatePresentationAndRefreshIncoming")
  note "apk has updatePresentationAndRefreshIncoming: $n"
  CALL_NATIVE_UNIT_LOG_DIR="$OUT/call-native-unit" bash scripts/test/run_call_native_unit_tests.sh > "$OUT/call_native_unit.out" 2>&1
  note "kotlin call tests exit=$? $(grep -E 'BUILD (SUCCESSFUL|FAILED)|tests completed' "$OUT/call_native_unit.out" | tail -2 | tr '\n' ' ')"
  for c in MknoonCallNativeBridgeTest MknoonCallLifecycleControllerTest MknoonCallNotificationFactoryTest; do
    f=$(ls -t build/app/test-results/testDebugUnitTest/TEST-*."$c".xml android/app/build/test-results/testDebugUnitTest/TEST-*."$c".xml 2>/dev/null | head -1)
    note "  $c: $([ -n "$f" ] && grep -oE 'tests="[0-9]+" skipped="[0-9]+" failures="[0-9]+" errors="[0-9]+"' "$f" | head -1) $([ -n "$f" ] && stat -f '%Sm' "$f")"
  done
fi
note "dart call UI tests"
"$FLUTTER" test --reporter expanded test/features/call/presentation/foreground_call_overlay_test.dart \
  test/features/call/presentation/locked_call_projection_test.dart \
  test/features/call/infrastructure/android_call_lifecycle_adapter_test.dart > "$OUT/dart_call_ui_tests.log" 2>&1
note "dart call UI tests exit=$? $(tail -1 "$OUT/dart_call_ui_tests.log" | cut -c1-160)"
note "$BUILD_NAME"
note "R28 BUILD DONE"
