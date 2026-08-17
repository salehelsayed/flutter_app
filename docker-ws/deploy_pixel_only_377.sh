#!/usr/bin/env bash
# Plan 377 device proof (TC-377-11): working-tree client to the Pixel ONLY,
# in-place update (data kept — the live bricked group "test" IS the fixture),
# provenance-verified per repo policy. Derived from deploy_pixel_only_321.sh;
# no smoke here — the TC-377-11 logcat gates in the plan are the acceptance.
set -uo pipefail
cd "$(dirname "$0")/.."

BUNDLE_ID=com.mknoon.app
SERIAL=21071FDF600CSC
RESULT_FILE="docker-ws/deploy_pixel_only_377_result.txt"
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
    --build-name="$BUILD_NAME" \
    || [ ! -f "$APK" ]; then
  note "P377 FAILED(build)"; exit 1
elif [ ! "$APK" -nt "$FRESH_MARK" ]; then
  note "P377 FAILED(stale-artifact)"; exit 1
fi

if ! adb -s "$SERIAL" install -r "$APK"; then
  note "P377 FAILED(install)"; exit 1
fi
if ! adb -s "$SERIAL" shell monkey -p "$BUNDLE_ID" -c android.intent.category.LAUNCHER 1 >/dev/null; then
  note "P377 FAILED(launch)"; exit 1
fi
GOT=$(adb -s "$SERIAL" shell dumpsys package "$BUNDLE_ID" | grep -m1 versionName | sed 's/.*versionName=//' | tr -d '\r ')
if [ "$GOT" = "$BUILD_NAME" ]; then
  note "P377 $SERIAL OK $BUILD_NAME (verified)"
else
  note "P377 FAILED(verify: installed '$GOT' != built '$BUILD_NAME')"; exit 1
fi
note "P377 PASS"
