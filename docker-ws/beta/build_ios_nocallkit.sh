#!/bin/bash
# Second iOS simulator build, identical to the beta build except
# VOICE_CALL_IOS_NATIVE_ENABLED=false, so calls use the in-app call screen
# instead of CallKit (the simulator's CallKit ends every call in ~1-2 s).
# Builds in the isolated copy; the live checkout is never written.
set -u
SRC=/Volumes/CrucialX9/flutter_app
DST=/Volumes/CrucialX9/flutter_app-beta0924
OUT="$SRC/artifacts/beta-20260924/build"
FLUTTER="$HOME/development/flutter-3.47.2/bin/flutter"
cd "$DST" || exit 2
STAMP=$(date +%y%m%d%H%M%S)
BUILD_NAME="$(cat "$OUT/build_name.txt" | sed -E 's/\.t[0-9]+$//').t${STAMP}.nock"
DEFINES=(--dart-define=E2E_TEST_MODE=true --dart-define=PRODUCTION_FCM=true)
for kv in $(/usr/bin/python3 -c 'import json,sys; [print(f"{k}={v}") for k,v in json.load(open(sys.argv[1])).items()]' "$SRC/tool/build/voice_call_release_defines.json"); do
  case "$kv" in VOICE_CALL_IOS_NATIVE_ENABLED=*) kv=VOICE_CALL_IOS_NATIVE_ENABLED=false;; esac
  DEFINES+=(--dart-define="$kv")
done
echo "defines: ${DEFINES[*]}" > "$OUT/defines_nocallkit.txt"
MARK=$(mktemp)
if "$FLUTTER" build ios --simulator --debug -t lib/main.dart "${DEFINES[@]}" \
    --build-name="$BUILD_NAME" --build-number="$STAMP" > "$OUT/ios_nocallkit_build.log" 2>&1 \
   && [ build/ios/iphonesimulator/Runner.app/Info.plist -nt "$MARK" ]; then
  rm -rf "$OUT/Runner-nocallkit.app"; cp -R build/ios/iphonesimulator/Runner.app "$OUT/Runner-nocallkit.app"
  echo "IOS-NOCALLKIT OK $BUILD_NAME" | tee "$OUT/result_nocallkit.txt"
else
  echo "IOS-NOCALLKIT FAILED (see ios_nocallkit_build.log)" | tee "$OUT/result_nocallkit.txt"
fi
