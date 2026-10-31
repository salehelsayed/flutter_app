#!/bin/bash
# Post a text Thought on an emulator: <serial> <text_without_spaces>
export ADB_SERVER_SOCKET=tcp:host.docker.internal:5037
S=${1:?}; T=${2:?}; D="$(dirname "$0")"
bash "$D/pixel_tap_desc.sh" $S "Share a thought" >/dev/null; sleep 3
B=$(adb -s $S shell uiautomator dump /sdcard/u.xml >/dev/null; adb -s $S shell cat /sdcard/u.xml | tr '>' '\n' | grep 'android.widget.EditText' | grep -oE 'bounds="[^"]*"' | head -1 | tr -c '0-9' ' ')
read x1 y1 x2 y2 <<<"$B"; [ -z "$x1" ] && { echo "NO FIELD"; bash "$D/pixel_ui_texts.sh" $S | head; exit 3; }
adb -s $S shell input tap $(( (x1+x2)/2 )) $(( (y1+y2)/2 )); sleep 1; adb -s $S shell input text "$T"; sleep 1
bash "$D/pixel_tap_desc.sh" $S 'content-desc="Share"'
