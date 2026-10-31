#!/bin/bash
# In the Android DocumentsUI picker: search this device for <name> and tap the result row. UI dump only, no screenshot.
#   step2_pick_search.sh <serial> <file-name>
export ADB_SERVER_SOCKET=${ADB_SERVER_SOCKET:-tcp:host.docker.internal:5037}
S="$1"; N="$2"; U="bash $(dirname "$0")/setA_ui.sh"
$U tap "$S" 'Search this device' >/dev/null || $U tap "$S" 'content-desc="Search"' >/dev/null || { echo "no search"; exit 3; }
sleep 2; adb -s "$S" shell input text "${N%.*}"; adb -s "$S" shell input keyevent 66; sleep 4
for i in 1 2 3; do
  adb -s "$S" shell rm -f /sdcard/u.xml; adb -s "$S" shell uiautomator dump /sdcard/u.xml >/dev/null 2>&1
  L=$(adb -s "$S" shell cat /sdcard/u.xml | tr '>' '\n' | grep -F "text=\"$N\"" | grep -v EditText | head -1)
  [ -n "$L" ] && break; sleep 3
done
[ -z "$L" ] && { echo "NOT FOUND $N"; exit 3; }
read -r x1 y1 x2 y2 <<<"$(echo "$L" | grep -o 'bounds="[^"]*"' | tr -c '0-9' ' ')"
adb -s "$S" shell input tap $(( (x1 + x2) / 2 )) $(( (y1 + y2) / 2 )); echo "picked $N $(date -u +%T)"
