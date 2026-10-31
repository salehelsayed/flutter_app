#!/bin/bash
# Usage: pixel_tap_desc.sh <serial> <content-desc or text substring>; taps the first matching node center.
S="$1"; Q="$2"
adb -s "$S" shell uiautomator dump /sdcard/u.xml >/dev/null 2>&1
B=$(adb -s "$S" shell cat /sdcard/u.xml | tr '>' '\n' | grep -F -- "$Q" | head -1 | grep -o 'bounds="[^"]*"' | head -1)
[ -z "$B" ] && { echo "NOT FOUND: $Q"; exit 3; }
read x1 y1 x2 y2 <<<"$(echo "$B" | tr -c '0-9' ' ')"
adb -s "$S" shell input tap $(( (x1+x2)/2 )) $(( (y1+y2)/2 ))
echo "tapped $Q at $(( (x1+x2)/2 )),$(( (y1+y2)/2 ))"
