#!/bin/bash
# Usage: pixel_group_send.sh <serial> <x> <y> <text> [wanted group]; from Orbit, opens the bubble at x,y, sends text, returns to Orbit.
# With a wanted group name, exits 6 (back on Orbit, nothing sent) when the bubble is a different group.
# Prints the group name and the UTC send time.
S="$1"; X="$2"; Y="$3"; T="$4"
dump() { adb -s "$S" shell rm -f /sdcard/u.xml; adb -s "$S" shell uiautomator dump /sdcard/u.xml >/dev/null 2>&1; adb -s "$S" shell cat /sdcard/u.xml 2>/dev/null | tr '>' '\n'; }
center() { read x1 y1 x2 y2 <<<"$(echo "$1" | grep -o 'bounds="[^"]*"' | head -1 | tr -c '0-9' ' ')"; echo "$(( (x1+x2)/2 )) $(( (y1+y2)/2 ))"; }
adb -s "$S" shell dumpsys window | grep mCurrentFocus | grep -q 'com.mknoon.app/' || { echo "NOT MKNOON"; exit 3; }
adb -s "$S" shell input tap "$X" "$Y"; sleep 3
U="$(dump)"
N=$(echo "$U" | grep -o 'content-desc="DelayG[0-9]"' | head -1 | cut -d'"' -f2)
[ -z "$N" ] && { echo "NO GROUP HEADER"; exit 4; }
[ -n "$5" ] && [ "$N" != "$5" ] && { adb -s "$S" shell input keyevent 4; sleep 3; echo "SKIP $N"; exit 6; }
E=$(echo "$U" | grep 'android.widget.EditText' | head -1)
adb -s "$S" shell input tap $(center "$E"); sleep 1
adb -s "$S" shell input text "$T"; sleep 1
B=$(dump | grep 'content-desc="Send message"' | head -1)
[ -z "$B" ] && { echo "NO SEND BUTTON"; exit 5; }
adb -s "$S" shell input tap $(center "$B"); TS=$(date -u +%FT%T.%3NZ); sleep 2
dump | grep 'android.widget.EditText' | head -1 | grep -q 'text=""' && echo "SENT $N $TS" || echo "UNSURE $N $TS"
adb -s "$S" shell input keyevent 111; sleep 1; adb -s "$S" shell input keyevent 4; sleep 3
