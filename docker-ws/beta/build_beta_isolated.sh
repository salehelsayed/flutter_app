#!/bin/bash
# Beta-test builds in an ISOLATED copy of the working tree, so the live
# checkout's build/, .dart_tool/ and Go libraries are never written.
#   1. rsync working tree -> /Volumes/CrucialX9/flutter_app-beta0924 (+ pub get)
#   2. Android debug APK (arm64) + iOS simulator debug app, built in the copy
#   3. copy artifacts to the live tree's artifacts/beta-20260924/build (gitignored)
# Debug + E2E_TEST_MODE for friend seeding; release voice-call flags;
# production relay (default addresses); PRODUCTION_FCM for push registration.
set -u
SRC=/Volumes/CrucialX9/flutter_app
DST=/Volumes/CrucialX9/flutter_app-beta0924
OUT="$SRC/artifacts/beta-20260924/build"
FLUTTER="$HOME/development/flutter-3.47.2/bin/flutter"
mkdir -p "$OUT"
RESULT="$OUT/result.txt"; : > "$RESULT"

if [ "${SKIP_SYNC:-0}" != 1 ]; then PROOF_DST="$DST" PROOF_MAX_GB=8 bash "$SRC/docker-ws/prepare_proof_checkout_5556.sh" > "$OUT/prepare.log" 2>&1
rc=$?; else rc=0; fi
tail -12 "$OUT/prepare.log"
if [ $rc -ne 0 ]; then echo "PREPARE FAILED rc=$rc" >> "$RESULT"; cat "$RESULT"; exit 1; fi

cd "$DST" || exit 2
STAMP=$(date +%y%m%d%H%M%S)
SHA=$(sed -n 's/^source_head_short=//p' .proof-checkout-provenance.txt)
DIRTY=$(sed -n 's/^source_dirty_files=//p' .proof-checkout-provenance.txt)
BUILD_NAME="1.0.0-${SHA}.d${DIRTY}.t${STAMP}"
echo "$BUILD_NAME" > "$OUT/build_name.txt"
cp .proof-checkout-provenance.txt "$OUT/provenance.txt"
# tool/build/ is skipped by the copy's 'build/' exclude, so read the release
# voice-call defines from the LIVE tree and pass them one by one.
DEFINES=(--dart-define=E2E_TEST_MODE=true --dart-define=PRODUCTION_FCM=true)
for kv in $(/usr/bin/python3 -c 'import json,sys; [print(f"{k}={v}") for k,v in json.load(open(sys.argv[1])).items()]' "$SRC/tool/build/voice_call_release_defines.json"); do
  DEFINES+=(--dart-define="$kv")
done
echo "defines: ${DEFINES[*]}" | tee "$OUT/defines.txt"
MARK=$(mktemp)

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
  if [ -d "$APP" ] && [ "$APP/Info.plist" -nt "$MARK" ]; then
    rm -rf "$OUT/Runner.app"; cp -R "$APP" "$OUT/Runner.app"; echo "IOS OK $BUILD_NAME" >> "$RESULT"
  else echo "IOS FAILED stale-artifact" >> "$RESULT"; fi
else echo "IOS FAILED build (see ios_build.log)" >> "$RESULT"; fi
cat "$RESULT"
