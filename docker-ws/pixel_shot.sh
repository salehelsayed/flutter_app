#!/bin/bash
# Usage: pixel_shot.sh <serial> <container dest png>; screenshot only when Mknoon is the focused window.
S="$1"; D="$2"
adb -s "$S" shell dumpsys window | grep mCurrentFocus | grep -q 'com.mknoon.app/' || { echo "NOT MKNOON FOREGROUND, no screenshot"; exit 3; }
adb -s "$S" shell screencap -p /sdcard/q.png && adb -s "$S" pull /sdcard/q.png "$D" | tail -1
