#!/bin/bash
# Chat-open bisect step (container side): B sends 3 unread messages, A gets the given APK installed over (upgrade, keep data), launched to Orbit.
#   bash docker-ws/bisect_step.sh <apk under repo> <tag>
set -uo pipefail
export ADB_SERVER_SOCKET=tcp:host.docker.internal:5037
A=emulator-5556; B=emulator-5558; D="$(dirname "$0")"
adb -s $A shell input keyevent 4 >/dev/null 2>&1; sleep 2
timeout 600 adb -s $A install -r "${1:?apk}" | tail -1
adb -s $A shell monkey -p com.mknoon.app -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
bash "$D/pixel_tap_desc.sh" $B "Open chat with bisectA" >/dev/null; sleep 3
for i in 1 2 3; do bash "$D/android_send_text.sh" $B "unread_${2:?tag}_$i" >/dev/null 2>&1; done
adb -s $B shell input keyevent 4; sleep 12
echo "A $(adb -s $A shell dumpsys package com.mknoon.app | grep -m1 versionCode | tr -s ' ')"
bash "$D/pixel_ui_texts.sh" $A | grep -m1 'Open chat with bisectB'
