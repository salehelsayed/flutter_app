#!/bin/bash
# Open the notification shade, tap the first notification whose text contains <substring>, print the focus after. UI dump only, never a screenshot.
#   setA_notif_tap.sh <serial> <substring>
export ADB_SERVER_SOCKET=${ADB_SERVER_SOCKET:-tcp:host.docker.internal:5037}
S="$1"; Q="$2"
adb -s "$S" shell cmd statusbar expand-notifications; sleep 2
adb -s "$S" shell rm -f /sdcard/u.xml; adb -s "$S" shell uiautomator dump /sdcard/u.xml >/dev/null 2>&1
L=$(adb -s "$S" shell cat /sdcard/u.xml | tr '>' '\n' | grep -F -- "$Q" | head -1)
if [ -z "$L" ]; then echo "NOT IN SHADE: $Q"; adb -s "$S" shell cmd statusbar collapse; exit 3; fi
read -r x1 y1 x2 y2 <<<"$(echo "$L" | grep -o 'bounds="[^"]*"' | head -1 | tr -c '0-9' ' ')"
adb -s "$S" shell input tap $(( (x1+x2)/2 )) $(( (y1+y2)/2 )); echo "tapped notification $(date -u +%T)"; sleep 4
adb -s "$S" shell dumpsys window | grep mCurrentFocus
