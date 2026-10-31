#!/bin/bash
# Usage: android_send_text.sh <serial> <text-without-spaces-or-%s>; types into the chat input (EditText) of the open Mknoon chat and taps Send message.
S="$1"; T="$2"
adb -s "$S" shell uiautomator dump /sdcard/u.xml >/dev/null 2>&1
B=$(adb -s "$S" shell cat /sdcard/u.xml | tr '>' '\n' | grep 'EditText' | head -1 | grep -o 'bounds="[^"]*"')
[ -z "$B" ] && { echo "NO INPUT"; exit 3; }
read x1 y1 x2 y2 <<<"$(echo "$B" | tr -c '0-9' ' ')"
adb -s "$S" shell input tap $(( (x1+x2)/2 )) $(( (y1+y2)/2 )); sleep 1
adb -s "$S" shell input text "$T"; sleep 1
bash "$(dirname "$0")/pixel_tap_desc.sh" "$S" 'Send message'
