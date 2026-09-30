#!/bin/bash
# Beta rebuild WITH the fix branch: current working tree (rsync to the isolated
# copy) + patch 237e88dd5..<fix sha> ($1, default 0cf14ffdb) applied in the copy only. Builds:
#   Android debug APK, iOS sim (CallKit on = release flags), iOS sim no-CallKit.
# The live checkout is never written (except artifacts/beta-20260925, gitignored).
set -u
SRC=/Volumes/CrucialX9/flutter_app
DST=/Volumes/CrucialX9/flutter_app-beta0924
OUT="$SRC/artifacts/beta-20260925/build"
FIX_SHA="${1:-0cf14ffdb}"
PATCH="$SRC/docker-ws/beta/fixes_237e88dd5_${FIX_SHA}.patch"
FLUTTER="$HOME/development/flutter-3.47.2/bin/flutter"
mkdir -p "$OUT"; printf '*\n' > "$SRC/artifacts/beta-20260925/.gitignore"
RESULT="$OUT/result.txt"; : > "$RESULT"

PROOF_DST="$DST" PROOF_MAX_GB=8 bash "$SRC/docker-ws/prepare_proof_checkout_5556.sh" > "$OUT/prepare.log" 2>&1 \
  || { echo "PREPARE FAILED" >> "$RESULT"; cat "$RESULT"; exit 1; }
cd "$DST" || exit 2
if git apply --check "$PATCH" > "$OUT/patch.log" 2>&1 && git apply "$PATCH" >> "$OUT/patch.log" 2>&1; then
  echo "PATCH OK $(grep -c '^diff --git' "$PATCH") files" >> "$RESULT"
else
  echo "PATCH FAILED (see patch.log)" >> "$RESULT"; cat "$RESULT"; exit 1
fi
STAMP=$(date +%y%m%d%H%M%S)
SHA=$(sed -n 's/^source_head_short=//p' .proof-checkout-provenance.txt)
DIRTY=$(sed -n 's/^source_dirty_files=//p' .proof-checkout-provenance.txt)
BUILD_NAME="1.0.0-${SHA}.d${DIRTY}.fix-${FIX_SHA}.t${STAMP}"
echo "$BUILD_NAME" > "$OUT/build_name.txt"
{ cat .proof-checkout-provenance.txt; echo "patch=fixes_237e88dd5_${FIX_SHA} (branch fix/beta-call-labels-20260924 @ ${FIX_SHA})"; } > "$OUT/provenance.txt"

base_defines() {
  echo --dart-define=E2E_TEST_MODE=true --dart-define=PRODUCTION_FCM=true
  /usr/bin/python3 -c 'import json,sys
for k,v in json.load(open(sys.argv[1])).items():
    if sys.argv[2]=="nock" and k=="VOICE_CALL_IOS_NATIVE_ENABLED": v="false"
    print(f"--dart-define={k}={v}")' "$SRC/tool/build/voice_call_release_defines.json" "$1"
}
MARK=$(mktemp)

echo "=== android"
if "$FLUTTER" build apk --debug --target-platform=android-arm64 -t lib/main.dart $(base_defines rel) \
    --android-project-arg=enableAndroidNativeCalls=true --build-name="$BUILD_NAME" > "$OUT/android_build.log" 2>&1 \
   && [ build/app/outputs/flutter-apk/app-debug.apk -nt "$MARK" ]; then
  cp build/app/outputs/flutter-apk/app-debug.apk "$OUT/beta-android.apk"; echo "ANDROID OK" >> "$RESULT"
else echo "ANDROID FAILED" >> "$RESULT"; fi

for v in ANDROID_ONLY_SKIP; do [ "$v" = ANDROID_ONLY_SKIP ] && break
  echo "=== ios $v"
  M2=$(mktemp)
  if "$FLUTTER" build ios --simulator --debug -t lib/main.dart $(base_defines $v) \
      --build-name="$BUILD_NAME" --build-number="$STAMP" > "$OUT/ios_${v}_build.log" 2>&1 \
     && [ build/ios/iphonesimulator/Runner.app/Info.plist -nt "$M2" ]; then
    rm -rf "$OUT/Runner-$v.app"; cp -R build/ios/iphonesimulator/Runner.app "$OUT/Runner-$v.app"; echo "IOS-$v OK" >> "$RESULT"
  else echo "IOS-$v FAILED" >> "$RESULT"; fi
done
echo "$BUILD_NAME" >> "$RESULT"
cat "$RESULT"
