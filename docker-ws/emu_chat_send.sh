#!/bin/bash
# Usage: emu_chat_send.sh <serial> <text>; on an open chat screen, types the text and taps Send. Prints the UTC send time.
S="$1"; T="$2"
dump() { adb -s "$S" shell rm -f /sdcard/u.xml; adb -s "$S" shell uiautomator dump /sdcard/u.xml >/dev/null 2>&1; adb -s "$S" shell cat /sdcard/u.xml 2>/dev/null | tr '>' '\n'; }
center() { read x1 y1 x2 y2 <<<"$(echo "$1" | grep -o 'bounds="[^"]*"' | head -1 | tr -c '0-9' ' ')"; echo "$(( (x1+x2)/2 )) $(( (y1+y2)/2 ))"; }
adb -s "$S" shell dumpsys window | grep mCurrentFocus | grep -q 'com.mknoon.app/' || { echo "NOT MKNOON"; exit 3; }
E=$(dump | grep 'android.widget.EditText' | head -1); [ -z "$E" ] && { echo "NO INPUT"; exit 4; }
adb -s "$S" shell input tap $(center "$E"); sleep 1
adb -s "$S" shell input text "$T"; sleep 1
B=$(dump | grep 'content-desc="Send message"' | head -1); [ -z "$B" ] && { echo "NO SEND BUTTON"; exit 5; }
adb -s "$S" shell input tap $(center "$B"); TS=$(date -u +%FT%T.%3NZ); sleep 2
dump | grep 'android.widget.EditText' | head -1 | grep -q 'text=""' && echo "SENT $TS" || echo "UNSURE $TS"
