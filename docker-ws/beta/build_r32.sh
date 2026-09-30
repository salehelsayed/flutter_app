#!/bin/bash
# R2-9 W3 validation build (2026-09-30, from build_r31.sh: + headless ringing reply): killed + locked Android call. Same as the R2-8 build, plus the
# headless admission timing markers and their two Dart test files. Syncs the live working
# tree into the isolated copy, builds the Android debug APK and the iOS simulator app (in-app call UI; the shared Dart
# call path changed), runs the Kotlin call unit tests and the changed Dart call tests in the copy. Same settings as
# round 1: debug + E2E_TEST_MODE, release voice-call defines, PRODUCTION_FCM, production relay.
# The live checkout is only read. Output: artifacts/beta-20260928/build-r2-11/{result.txt,...}
set -u
SRC=/Volumes/CrucialX9/flutter_app
DST=/Volumes/CrucialX9/flutter_app-beta0924
OUT="$SRC/artifacts/beta-20260928/build-r2-11"
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
for m in "lib/features/call/infrastructure/android_call_token_coordinator.dart:final class AndroidFcmTokenReader" \
         "lib/app/bootstrap/production_application_bootstrap.dart:rotateOnFirstRead: pushRelayRegistrationProof == null" \
         "lib/features/call/application/handle_incoming_call_signal.dart:_updateAndroidAuthenticatedContactSafely" \
         "$CALL/MknoonCallLifecycleController.kt:fun updateAuthenticatedContactName" \
         "$CALL/MknoonCallNativeBridge.kt:\"updateAuthenticatedContactName\" ->" \
         "$CALL/MknoonCallLifecycleController.kt:fun updatePresentationAndRefreshIncoming" \
         "lib/features/call/presentation/foreground_call_overlay.dart:_nameLoaded ? _contactDisplayName" \
         "lib/app/bootstrap/production_headless_call_admission.dart:event: 'CALL_HEADLESS_ADMISSION_STEP'" \
         "lib/features/call/infrastructure/headless_call_admission_entrypoint.dart:event: 'CALL_HEADLESS_ADMISSION_ENTRY'" \
         "lib/features/call/application/headless_call_ringing_reply.dart:class"; do
  grep -qF "${m#*:}" "${m%%:*}" || { note "R2-8 MARKER MISSING ${m#*:}"; exit 1; }
done
if grep -qE "_report\('unchanged'\)" lib/features/call/infrastructure/android_call_token_coordinator.dart; then
  note "R2-8 MARKER PROBLEM: the call token coordinator still skips unchanged tokens"; exit 1
fi
note "R2-8 fix markers and R2-9 headless admission timing markers present"

STAMP=$(date +%y%m%d%H%M%S)
SHA=$(sed -n 's/^source_head_short=//p' .proof-checkout-provenance.txt)
DIRTY=$(sed -n 's/^source_dirty_files=//p' .proof-checkout-provenance.txt)
BUILD_NAME="1.0.0-${SHA}.d${DIRTY}.t${STAMP}"
echo "$BUILD_NAME" > "$OUT/build_name.txt"
defines() {  # defines <and|nock>
  echo --dart-define=E2E_TEST_MODE=true --dart-define=PRODUCTION_FCM=true
  /usr/bin/python3 -c 'import json,sys
for k,v in json.load(open(sys.argv[1])).items():
    if sys.argv[2]=="nock" and k=="VOICE_CALL_IOS_NATIVE_ENABLED": v="false"
    print(f"--dart-define={k}={v}")' "$SRC/tool/build/voice_call_release_defines.json" "$1"
}
defines and > "$OUT/defines_android.txt"; defines nock > "$OUT/defines_ios.txt"

note "android build $BUILD_NAME"
M=$(mktemp)
if "$FLUTTER" build apk --debug --target-platform=android-arm64 -t lib/main.dart $(defines and) \
    --android-project-arg=enableAndroidNativeCalls=true --build-name="$BUILD_NAME" > "$OUT/android_build.log" 2>&1 \
   && [ build/app/outputs/flutter-apk/app-debug.apk -nt "$M" ]; then
  cp build/app/outputs/flutter-apk/app-debug.apk "$OUT/beta-android.apk"
  T=$(mktemp -d); unzip -qo "$OUT/beta-android.apk" 'lib/arm64-v8a/*' -d "$T" 2>/dev/null
  n=$(cat "$T"/lib/arm64-v8a/*.so 2>/dev/null | LC_ALL=C grep -a -c "$NEW_GO"); rm -rf "$T"
  note "ANDROID OK go_new_symbol=$n sha256=$(shasum -a 256 "$OUT/beta-android.apk" | cut -c1-16)"
else
  note "ANDROID FAILED (see android_build.log)"
fi

if grep -q "ANDROID OK" "$RESULT"; then
  n=$(unzip -p "$OUT/beta-android.apk" 'classes*.dex' 2>/dev/null | LC_ALL=C grep -a -c "updateAuthenticatedContactName")
  note "apk has updateAuthenticatedContactName: $n"
  CALL_NATIVE_UNIT_LOG_DIR="$OUT/call-native-unit" bash scripts/test/run_call_native_unit_tests.sh > "$OUT/call_native_unit.out" 2>&1
  note "kotlin call tests exit=$? $(grep -E 'BUILD (SUCCESSFUL|FAILED)|tests completed' "$OUT/call_native_unit.out" | tail -2 | tr '\n' ' ')"
  for c in MknoonCallNativeBridgeTest MknoonCallLifecycleControllerTest MknoonCallNotificationFactoryTest; do
    f=$(ls -t build/app/test-results/testDebugUnitTest/TEST-*."$c".xml android/app/build/test-results/testDebugUnitTest/TEST-*."$c".xml 2>/dev/null | head -1)
    note "  $c: $([ -n "$f" ] && grep -oE 'tests="[0-9]+" skipped="[0-9]+" failures="[0-9]+" errors="[0-9]+"' "$f" | head -1) $([ -n "$f" ] && stat -f '%Sm' "$f")"
  done
fi
note "dart call tests"
"$FLUTTER" test --reporter expanded \
  test/features/call/infrastructure/android_call_token_coordinator_test.dart \
  test/features/call/infrastructure/android_call_lifecycle_adapter_test.dart \
  test/features/call/application/handle_incoming_call_signal_test.dart \
  test/core/bootstrap/call_signaling_composition_test.dart \
  test/core/bootstrap/production_application_bootstrap_phase_contract_test.dart \
  test/features/call/presentation/foreground_call_overlay_test.dart \
  test/features/call/presentation/locked_call_projection_test.dart \
  test/core/bootstrap/production_headless_call_admission_test.dart \
  test/features/call/infrastructure/headless_call_admission_entrypoint_test.dart \
  test/features/call/application/headless_call_ringing_reply_test.dart > "$OUT/dart_call_tests.log" 2>&1
note "dart call tests exit=$? $(tail -1 "$OUT/dart_call_tests.log" | cut -c1-160)"

note "ios go bindings"
if ! bash scripts/ensure_go_ios_bindings.sh > "$OUT/ios_go_bindings.log" 2>&1; then
  note "IOS FAILED (go bindings, see ios_go_bindings.log)"
else
  note "ios build (in-app call UI)"
  M=$(mktemp)
  if "$FLUTTER" build ios --simulator --debug -t lib/main.dart $(defines nock) \
      --build-name="$BUILD_NAME" --build-number="$STAMP" > "$OUT/ios_build.log" 2>&1 \
     && [ build/ios/iphonesimulator/Runner.app/Info.plist -nt "$M" ]; then
    rm -rf "$OUT/Runner-nock.app"; cp -R build/ios/iphonesimulator/Runner.app "$OUT/Runner-nock.app"
    g=0; s=0
    for f in $(find "$OUT/Runner-nock.app" -type f \( -name Runner -o -name Runner.debug.dylib -o -name GoMknoon \)); do
      g=$(( g + $(LC_ALL=C grep -a -c runtime.goexit "$f") )); s=$(( s + $(LC_ALL=C grep -a -c "$NEW_GO" "$f") ))
    done
    note "IOS OK go_marker=$g go_new_symbol=$s"
  else
    note "IOS FAILED (see ios_build.log)"
  fi
fi
note "$BUILD_NAME"
note "R32 BUILD DONE"
