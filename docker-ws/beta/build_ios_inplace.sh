#!/bin/bash
# Build the iOS simulator apps (nock = in-app call UI, rel = CallKit on) in the
# isolated copy AS IT IS: same synced tree (00:05Z) + patch 362d930e2 as the installed
# Android APK, so both devices run the same source. No re-sync, no re-patch.
# Usage: build_ios_inplace.sh [variant ...]   (default: nock rel)
# A partial rebuild (e.g. "rel") reuses the name/number of the apps already built.
# The previous apps are kept as Runner-<v>-c8be267bd.app. Result: build/ios_result.txt
set -u
SRC=/Volumes/CrucialX9/flutter_app
DST=/Volumes/CrucialX9/flutter_app-beta0924
OUT="$SRC/artifacts/beta-20260925/build"
FLUTTER="$HOME/development/flutter-3.47.2/bin/flutter"
RESULT="$OUT/ios_result.txt"
VARIANTS="${*:-nock rel}"
cd "$DST" || { echo "NO COPY" >> "$RESULT"; exit 2; }
grep -q "synced_at=2026-09-26T00:05:14Z" .proof-checkout-provenance.txt || { echo "COPY CHANGED" >> "$RESULT"; exit 1; }
grep -q CALL_INCOMING_SIGNAL_NOT_ACCEPTED lib/features/call/application/handle_incoming_call_signal.dart \
  || { echo "PATCH MISSING" >> "$RESULT"; exit 1; }
if [ "$VARIANTS" = "nock rel" ] || [ ! -s "$OUT/ios_build_name.txt" ]; then
  : > "$RESULT"
  STAMP=$(date +%y%m%d%H%M%S)
  SHA=$(sed -n 's/^source_head_short=//p' .proof-checkout-provenance.txt)
  DIRTY=$(sed -n 's/^source_dirty_files=//p' .proof-checkout-provenance.txt)
  BUILD_NAME="1.0.0-${SHA}.d${DIRTY}.fix-362d930e2.t${STAMP}"
  echo "$BUILD_NAME" > "$OUT/ios_build_name.txt"
else
  BUILD_NAME=$(cat "$OUT/ios_build_name.txt"); STAMP=${BUILD_NAME##*.t}
  echo "partial rebuild ($VARIANTS) as $BUILD_NAME" >> "$RESULT"
fi

base_defines() {
  echo --dart-define=E2E_TEST_MODE=true --dart-define=PRODUCTION_FCM=true
  /usr/bin/python3 -c 'import json,sys
for k,v in json.load(open(sys.argv[1])).items():
    if sys.argv[2]=="nock" and k=="VOICE_CALL_IOS_NATIVE_ENABLED": v="false"
    print(f"--dart-define={k}={v}")' "$SRC/tool/build/voice_call_release_defines.json" "$1"
}
go_linked() {  # prints the Go runtime marker count of an app (0 = Go bridge compiled out)
  local n=0 f
  for f in "$1/Runner" "$1/Runner.debug.dylib"; do
    [ -f "$f" ] && n=$(( n + $(LC_ALL=C grep -c -a "runtime.goexit" "$f") ))
  done
  echo $n
}

for v in $VARIANTS; do
  [ -d "$OUT/Runner-$v.app" ] && [ ! -d "$OUT/Runner-$v-c8be267bd.app" ] && mv "$OUT/Runner-$v.app" "$OUT/Runner-$v-c8be267bd.app"
done
for v in $VARIANTS; do
  M2=$(mktemp)
  if "$FLUTTER" build ios --simulator --debug -t lib/main.dart $(base_defines $v) \
      --build-name="$BUILD_NAME" --build-number="$STAMP" > "$OUT/ios_${v}_build.log" 2>&1 \
     && [ build/ios/iphonesimulator/Runner.app/Info.plist -nt "$M2" ]; then
    rm -rf "$OUT/Runner-$v.app"; cp -R build/ios/iphonesimulator/Runner.app "$OUT/Runner-$v.app"
    echo "IOS-$v OK go_marker=$(go_linked "$OUT/Runner-$v.app")" >> "$RESULT"
  else echo "IOS-$v FAILED" >> "$RESULT"; fi
done
echo "$BUILD_NAME" >> "$RESULT"
echo "IOS BUILD DONE" >> "$RESULT"
cat "$RESULT"
