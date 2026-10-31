#!/bin/bash
# On an open Thought card: type a reply and tap the send button found by its description. <serial> <text>
export ADB_SERVER_SOCKET=tcp:host.docker.internal:5037
S=${1:?}; T=${2:?}
F=$(adb -s $S shell uiautomator dump /sdcard/u.xml >/dev/null; adb -s $S shell cat /sdcard/u.xml | tr '>' '\n' | grep 'android.widget.EditText' | grep -oE 'bounds="[^"]*"' | head -1 | tr -c '0-9' ' ')
read x1 y1 x2 y2 <<<"$F"; [ -z "$x1" ] && { echo "NO FIELD"; exit 3; }
adb -s $S shell input tap $(( (x1+x2)/2 )) $(( (y1+y2)/2 )); sleep 1; adb -s $S shell input text "$T"; sleep 1
B=$(adb -s $S shell uiautomator dump /sdcard/u.xml >/dev/null; adb -s $S shell cat /sdcard/u.xml | tr '>' '\n' | grep -iE 'content-desc="Send' | grep -oE 'bounds="[^"]*"' | head -1 | tr -c '0-9' ' ')
read x1 y1 x2 y2 <<<"$B"; [ -z "$x1" ] && { echo "NO SEND"; exit 4; }
adb -s $S shell input tap $(( (x1+x2)/2 )) $(( (y1+y2)/2 )); echo "sent"
