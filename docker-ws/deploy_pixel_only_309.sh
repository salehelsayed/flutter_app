#!/usr/bin/env bash
# Plan 309 re-land STAGE 1: client to the Pixel ONLY (staged protocol — one
# device + smoke before fleet, client before relay). Derived from
# deploy_all_phones.sh; in-place update, data kept, provenance-verified.
set -uo pipefail
cd "$(dirname "$0")/.."

BUNDLE_ID=com.mknoon.app
SERIAL=21071FDF600CSC
RESULT_FILE="docker-ws/deploy_pixel_only_309_result.txt"
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
  note "STAGE1 FAILED(build)"; exit 1
elif [ ! "$APK" -nt "$FRESH_MARK" ]; then
  note "STAGE1 FAILED(stale-artifact)"; exit 1
fi

if ! adb -s "$SERIAL" install -r "$APK"; then
  note "STAGE1 FAILED(install)"; exit 1
fi
if ! adb -s "$SERIAL" shell monkey -p "$BUNDLE_ID" -c android.intent.category.LAUNCHER 1 >/dev/null; then
  note "STAGE1 FAILED(launch)"; exit 1
fi
GOT=$(adb -s "$SERIAL" shell dumpsys package "$BUNDLE_ID" | grep -m1 versionName | sed 's/.*versionName=//' | tr -d '\r ')
if [ "$GOT" = "$BUILD_NAME" ]; then
  note "STAGE1 $SERIAL OK $BUILD_NAME (verified)"
else
  note "STAGE1 FAILED(verify: installed '$GOT' != built '$BUILD_NAME')"; exit 1
fi

# --- Smoke: the exact 07-31 breakage repro — background -> reopen -> loads ---
sleep 6
adb -s "$SERIAL" shell uiautomator dump /sdcard/smoke309_a.xml >/dev/null
A=$(adb -s "$SERIAL" shell cat /sdcard/smoke309_a.xml)
case "$A" in
  *"Open chat with"*|*"Show all chats"*) note "SMOKE launch-load OK";;
  *) note "SMOKE FAILED(initial load: no chat UI in dump)"; exit 1;;
esac
adb -s "$SERIAL" shell input keyevent KEYCODE_HOME
sleep 4
adb -s "$SERIAL" shell monkey -p "$BUNDLE_ID" -c android.intent.category.LAUNCHER 1 >/dev/null
sleep 6
adb -s "$SERIAL" shell uiautomator dump /sdcard/smoke309_b.xml >/dev/null
B=$(adb -s "$SERIAL" shell cat /sdcard/smoke309_b.xml)
case "$B" in
  *"Open chat with"*|*"Show all chats"*) note "SMOKE background-reopen-load OK (07-31 repro passes)";;
  *) note "SMOKE FAILED(background->reopen: no chat UI in dump)"; exit 1;;
esac
note "STAGE1 PASS"
