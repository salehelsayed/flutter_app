#!/bin/bash
# R2-1 fix validation builds (2026-09-28). Syncs the live working tree (main + uncommitted work, incl. the R2-1 fix)
# into the isolated copy, then builds the Android debug APK and the iOS simulator app
# with the in-app call UI (simulator CallKit ends every call). Same settings as round 1:
# debug + E2E_TEST_MODE, release voice-call defines, PRODUCTION_FCM, production relay.
# The live checkout is only read. Output: artifacts/beta-20260927/build/{result.txt,...}
set -u
SRC=/Volumes/CrucialX9/flutter_app
DST=/Volumes/CrucialX9/flutter_app-beta0924
OUT="$SRC/artifacts/beta-20260928/build"
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
for m in "lib/features/call/application/handle_incoming_call_signal.dart:CALL_INCOMING_SIGNAL_NOT_ACCEPTED" \
         "$CALL/MknoonCallAndroidRuntime.kt:MKNOON_TELECOM_REGISTRATION_TIMEOUT_MS" \
         "$CALL/MknoonCallLifecycleController.kt:dropDeferredAnswer" \
         "lib/features/groups/application/group_message_listener_system_transition_processor.dart:relaxTerminalPreTransitionHash"; do
  grep -q "${m##*:}" "${m%%:*}" || { note "FIX MARKER MISSING ${m##*:}"; exit 1; }
done
note "fix markers present (B, B5, B8, R2-1)"

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
  note "ANDROID OK go_new_symbol=$n"
else
  note "ANDROID FAILED (see android_build.log)"
fi

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
note "R2FIX BUILD DONE"
