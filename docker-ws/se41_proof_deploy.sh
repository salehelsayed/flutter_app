#!/bin/bash
# SE-41 T4b device proof: build the current tree and install it on the iPhone 13
# (release, FDC_FLOW_LOG) and the Pixel 6 (debug APK with MKNOON_UPDATE_CHECK=on,
# because the Pixel holds a debug-signed install and a release APK would need an
# uninstall). App data is kept on both. Usage: host-run bash docker-ws/se41_proof_deploy.sh [ios|pixel|both]
# Progress: build/se41_proof_deploy.log (bridge output is buffered).
set -uo pipefail
cd "$(dirname "$0")/.."
. "$(dirname "$0")/_flutter_sdk_env.sh"
LEG="${1:-both}"
LOG=build/se41_proof_deploy.log
mkdir -p build
: > "$LOG"
note() { echo "$*" | tee -a "$LOG"; }
note "=== start $(date -u +%FT%TZ) leg=$LEG head=$(git rev-parse --short HEAD) dirty=$(git status --porcelain | wc -l | tr -d ' ')"

if [ "$LEG" = ios ] || [ "$LEG" = both ]; then
  bash docker-ws/build_ios_flowlog.sh >> "$LOG" 2>&1 || { note "SE41 IOS BUILD FAILED"; exit 1; }
  IPHONE_UDIDS=00008110-00184D622289801E bash docker-ws/install_iphones_keep_identity.sh >> "$LOG" 2>&1
  note "SE41 IOS INSTALL EXIT $?"
fi

if [ "$LEG" = pixel ] || [ "$LEG" = both ]; then
  SERIAL=21071FDF600CSC
  GIT_SHA=$(git rev-parse --short HEAD)
  GIT_DIRTY=$(git status --porcelain | wc -l | tr -d ' ')
  BUILD_NAME="1.0.0-${GIT_SHA}.d${GIT_DIRTY}.se41.t$(date +%y%m%d%H%M%S)"
  FRESH_MARK=$(mktemp)
  APK=build/app/outputs/flutter-apk/app-debug.apk
  if flutter build apk --debug --target-platform=android-arm64 --target=lib/main.dart \
      --dart-define-from-file=tool/build/voice_call_release_defines.json \
      --dart-define=MKNOON_UPDATE_CHECK=on \
      --android-project-arg=enableAndroidNativeCalls=true \
      --build-name="$BUILD_NAME" >> "$LOG" 2>&1 && [ "$APK" -nt "$FRESH_MARK" ]; then
    adb -s "$SERIAL" install -r "$APK" >> "$LOG" 2>&1 || { note "SE41 PIXEL INSTALL FAILED"; exit 1; }
    adb -s "$SERIAL" shell monkey -p com.mknoon.app -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
    GOT=$(adb -s "$SERIAL" shell dumpsys package com.mknoon.app | grep -m1 versionName | sed 's/.*versionName=//' | tr -d '\r ')
    if [ "$GOT" = "$BUILD_NAME" ]; then note "SE41 PIXEL OK $BUILD_NAME"; else note "SE41 PIXEL VERIFY FAILED got=$GOT want=$BUILD_NAME"; fi
  else
    note "SE41 PIXEL BUILD FAILED"
  fi
fi
grep -E "PROVENANCE|IOS BUILT|OK|FAILED|SE41" "$LOG" | tail -20
