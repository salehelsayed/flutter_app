#!/bin/bash
# Plan 406: in-place update both emulators to the E2E-free APKs (identity,
# friendship and group kept), then show each one's My QR for the iPhone.
set -u
. /Volumes/CrucialX9/flutter_app/docker-ws/beta/beta_env.sh
ADBB=$ANDROID_HOME/platform-tools/adb
ART=/Volumes/CrucialX9/flutter_app/docker-ws/beta/wave5/g406
W=/Volumes/CrucialX9/flutter_app/docker-ws/beta/wave5
for pair in emulator-5554:old406m emulator-5556:new406m; do
  S=${pair%%:*}; A=${pair##*:}
  $ADBB -s $S install -r -g "$ART/$A.apk" | tail -1
  echo "$S $($ADBB -s $S shell dumpsys package com.mknoon.app | grep -m1 versionName | tr -d ' \r')"
  maestro --device $S test "$W/g406_qr.yaml" >/dev/null 2>&1; echo "$S my-QR flow exit=$?"
done
