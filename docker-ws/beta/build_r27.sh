#!/bin/bash
# R2-4 follow-up 2 (15 fps cap) + R2-6 follow-up 2 validation builds (2026-09-28). Syncs the live working tree (main + uncommitted work, incl. the R2-1,
# R2-2, R2-3, R2-4 follow-up and R2-6 fixes) into the isolated copy, then builds the Android debug APK and the iOS simulator app
# with the in-app call UI (simulator CallKit ends every call). Same settings as round 1:
# debug + E2E_TEST_MODE, release voice-call defines, PRODUCTION_FCM, production relay.
# The live checkout is only read. Output: artifacts/beta-20260928/build-r2-7/{result.txt,...}
set -u
SRC=/Volumes/CrucialX9/flutter_app
DST=/Volumes/CrucialX9/flutter_app-beta0924
OUT="$SRC/artifacts/beta-20260928/build-r2-7"
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
         "lib/features/groups/application/group_message_listener_system_transition_processor.dart:relaxTerminalPreTransitionHash" \
         "third_party/bonsoir_darwin/darwin/Classes/Discovery/BonsoirServiceDiscovery.swift:fr.skyost.bonsoir.discovery.resolve" \
         "lib/core/media/audio_recorder_service.dart:prepareForCall" \
         "lib/features/call/infrastructure/call_media_conflict_adapter.dart:prepareForCall" \
         "lib/app/bootstrap/production_call_signaling_graph.dart:microphoneCaptureLeases?.prepareForCall" \
         "lib/features/conversation/presentation/screens/conversation_wired.dart:CONV_FL_RECORD_CALL_INTERRUPTED" \
         "lib/features/groups/presentation/screens/group_conversation_wired.dart:GROUP_CONV_FL_RECORD_CALL_INTERRUPTED" \
         "lib/core/media/image_processor.dart:VideoProcessingTimeoutException" \
         "lib/core/media/image_processor.dart:videoStallTimeout" \
         "lib/features/conversation/presentation/screens/conversation_wired.dart:_showVideoProcessingTimeout" \
         "lib/features/groups/presentation/screens/group_conversation_wired.dart:_showVideoProcessingTimeout" \
         "lib/features/share/application/share_batch_delivery_coordinator.dart:skippedStalledVideoCount" \
         "third_party/video_compress/android/build.gradle:transcoder:0.11.2" \
         "third_party/video_compress/android/src/main/kotlin/com/example/video_compress/VideoCompressPlugin.kt:MonotonicTimeInterpolator()" \
         "lib/core/media/image_processor.dart:VideoProcessingUnavailableException" \
         "lib/core/widgets/video_processing_notice.dart:showVideoProcessingNotice" \
         "android/app/src/main/kotlin/com/mknoon/app/call/MknoonCallNotificationFactory.kt:callerName(nativeCallId)" \
         "android/app/src/main/kotlin/com/mknoon/app/call/MknoonCallNativeBridge.kt:Refresh its person" \
         "third_party/video_compress/android/src/main/kotlin/com/example/video_compress/VideoCompressPlugin.kt:safeFrameRate" \
         "third_party/video_compress/android/src/main/kotlin/com/example/video_compress/TranscodeOutputGuard.kt:class TranscodeOutputGuard" \
         "lib/features/call/presentation/locked_call_projection.dart:await publish(_avatar)" \
         "lib/features/call/infrastructure/android_call_lifecycle_adapter.dart:_flushLockedPresentation" \
         "android/app/src/main/kotlin/com/mknoon/app/call/MknoonCallNativeBridge.kt:updatePresentation accepted="; do
  grep -q "${m##*:}" "${m%%:*}" || { note "FIX MARKER MISSING ${m##*:}"; exit 1; }
done
note "fix markers present (B, B5, B8, R2-1..R2-3, R2-4 follow-up 2, R2-6 follow-up 2)"

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

if grep -q "ANDROID OK" "$RESULT"; then
  n=$(unzip -p "$OUT/beta-android.apk" 'classes*.dex' 2>/dev/null | LC_ALL=C grep -a -c "TranscodeOutputGuard")
  note "apk has TranscodeOutputGuard: $n"
  ./android/gradlew -p android --console=plain :app:dependencies --configuration debugRuntimeClasspath > "$OUT/deps.log" 2>&1
  note "transcoder resolved: $(grep -oE 'com\.otaliastudios:transcoder:[0-9.]+( -> [0-9.]+)?' "$OUT/deps.log" | sort -u | tr '\n' ' ')"
  CALL_NATIVE_UNIT_LOG_DIR="$OUT/call-native-unit" bash scripts/test/run_call_native_unit_tests.sh > "$OUT/call_native_unit.out" 2>&1
  note "kotlin call tests exit=$? $(grep -E 'BUILD (SUCCESSFUL|FAILED)|tests completed' "$OUT/call_native_unit.out" | tail -2 | tr '\n' ' ')"
  ./android/gradlew -p android --console=plain :video_compress:testDebugUnitTest > "$OUT/video_compress_unit.log" 2>&1
  note "video_compress unit tests exit=$? $(grep -E 'BUILD (SUCCESSFUL|FAILED)|tests completed|FAILED' "$OUT/video_compress_unit.log" | tail -2 | tr '\n' ' ')"
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
note "R27 BUILD DONE"
