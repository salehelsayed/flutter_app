#!/bin/bash
# Reset the scanner emulator to a fresh account and scan the camera poster QR.
#   host-run bash docker-ws/nc_new_scanner.sh <serial> <username>
S="$1"; N="$2"; D="$(dirname "$0")"
adb -s "$S" shell pm clear com.mknoon.app
adb -s "$S" shell monkey -p com.mknoon.app -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
for i in $(seq 1 30); do
  bash "$D/pixel_ui_texts.sh" "$S" 2>/dev/null | grep -q "I'm new here" && break
  sleep 2
done
bash "$D/android_onboard_scan.sh" "$S" "$N"
