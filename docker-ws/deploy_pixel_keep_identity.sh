#!/usr/bin/env bash
# Working-tree client to the Pixel ONLY, in-place update (app data and identity
# kept), provenance-verified per repo policy. Same build flags as the Pixel leg
# of deploy_all_phones.sh (voice-call defines + native calls), derived from
# deploy_pixel_only_377.sh. Run ON THE MAC or via host-run.
set -uo pipefail
cd "$(dirname "$0")/.."

BUNDLE_ID=com.mknoon.app
SERIAL=${PIXEL_SERIAL:-21071FDF600CSC}
RESULT_FILE="docker-ws/deploy_pixel_keep_identity_result.txt"
: > "$RESULT_FILE"
note() { echo "$*" | tee -a "$RESULT_FILE"; }

GIT_SHA=$(git rev-parse --short HEAD)
GIT_DIRTY=$(git status --porcelain | wc -l | tr -d ' ')
RUN_STAMP=$(date +%y%m%d%H%M%S)
BUILD_NAME="1.0.0-${GIT_SHA}"
[ "$GIT_DIRTY" != "0" ] && BUILD_NAME="${BUILD_NAME}.d${GIT_DIRTY}"
BUILD_NAME="${BUILD_NAME}.t${RUN_STAMP}"
FRESH_MARK=$(mktemp)
note "PROVENANCE sha=$GIT_SHA dirty_files=$GIT_DIRTY build_name=$BUILD_NAME date=$(date '+%Y-%m-%d %H:%M:%S')"

APK=build/app/outputs/flutter-apk/app-debug.apk
if ! flutter build apk --debug --target-platform=android-arm64 --target=lib/main.dart \
    --dart-define-from-file=tool/build/voice_call_release_defines.json \
    --android-project-arg=enableAndroidNativeCalls=true \
    --build-name="$BUILD_NAME" \
    || [ ! -f "$APK" ]; then
  note "PIXEL FAILED(build)"; exit 1
elif [ ! "$APK" -nt "$FRESH_MARK" ]; then
  note "PIXEL FAILED(stale-artifact)"; exit 1
fi

if ! adb -s "$SERIAL" install -r "$APK"; then
  note "PIXEL FAILED(install)"; exit 1
fi
if ! adb -s "$SERIAL" shell monkey -p "$BUNDLE_ID" -c android.intent.category.LAUNCHER 1 >/dev/null; then
  note "PIXEL FAILED(launch)"; exit 1
fi
GOT=$(adb -s "$SERIAL" shell dumpsys package "$BUNDLE_ID" | grep -m1 versionName | sed 's/.*versionName=//' | tr -d '\r ')
if [ "$GOT" = "$BUILD_NAME" ]; then
  note "PIXEL $SERIAL OK $BUILD_NAME (verified)"
else
  note "PIXEL FAILED(verify: installed '$GOT' != built '$BUILD_NAME')"; exit 1
fi
note "PIXEL PASS"
