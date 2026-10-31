#!/bin/bash
# Print the center "x y" of the first Mknoon element whose content-desc contains <text> (uiautomator dump), or nothing.
#   host-run bash docker-ws/pixel_row_center.sh <serial> <text>
S="$1"; T="$2"
adb -s "$S" shell rm -f /sdcard/u.xml; adb -s "$S" shell uiautomator dump /sdcard/u.xml >/dev/null 2>&1
L=$(adb -s "$S" shell cat /sdcard/u.xml | tr '>' '\n' | grep "content-desc=\"[^\"]*$T" | head -1)
[ -z "$L" ] && exit 1
read x1 y1 x2 y2 <<<"$(echo "$L" | grep -o 'bounds="[^"]*"' | tr -c '0-9' ' ')"
echo "$(( (x1+x2)/2 )) $(( (y1+y2)/2 ))"
