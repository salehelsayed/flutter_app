#!/bin/bash
# In the Android DocumentsUI picker, tap the row whose file name is <name> (scrolls up/down to find it). UI dump only, no screenshot.
#   setC_pick.sh <serial> <file-name>
export ADB_SERVER_SOCKET=${ADB_SERVER_SOCKET:-tcp:host.docker.internal:5037}
S="$1"; N="$2"
for sw in 0 up up up down down down down down down; do
  case $sw in up) adb -s "$S" shell input swipe 540 1100 540 1700 600; sleep 2;; down) adb -s "$S" shell input swipe 540 1700 540 1100 600; sleep 2;; esac
  adb -s "$S" shell rm -f /sdcard/u.xml; adb -s "$S" shell uiautomator dump /sdcard/u.xml >/dev/null 2>&1
  L=$(adb -s "$S" shell cat /sdcard/u.xml | tr '>' '\n' | grep -F "text=\"$N\"" | head -1)
  if [ -n "$L" ]; then
    read -r x1 y1 x2 y2 <<<"$(echo "$L" | grep -o 'bounds="[^"]*"' | tr -c '0-9' ' ')"
    [ "$y1" -lt 320 ] && { adb -s "$S" shell input swipe 540 1100 540 1500 600; sleep 2; continue; }
    adb -s "$S" shell input tap 300 $(( (y1 + y2) / 2 )); echo "picked $N $(date -u +%T)"; exit 0
  fi
done
echo "NOT FOUND $N"; exit 3
