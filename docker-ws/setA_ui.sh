#!/bin/bash
# Android UI helper for the setA-privintro run. Deletes the old dump first so a failed dump (Orbit) reads as EMPTY, not stale.
#   setA_ui.sh texts <serial>            focus line + non-empty text/content-desc (prints DUMP_FAILED when the dump fails)
#   setA_ui.sh tap <serial> <substring>  tap the first node whose line contains the substring
#   setA_ui.sh shot <serial> <png>       screenshot only when com.mknoon.app has focus and no shade/keyguard is up
#   setA_ui.sh send <serial> <text>      type (no spaces) into the composer and tap Send message
export ADB_SERVER_SOCKET=${ADB_SERVER_SOCKET:-tcp:host.docker.internal:5037}
CMD="$1"; S="$2"
dump() {
  timeout 15 adb -s "$S" shell rm -f /sdcard/u.xml
  timeout 20 adb -s "$S" shell uiautomator dump /sdcard/u.xml >/dev/null 2>&1
  timeout 15 adb -s "$S" shell cat /sdcard/u.xml 2>/dev/null | tr '>' '\n'
}
center() { read -r x1 y1 x2 y2 <<<"$(echo "$1" | grep -o 'bounds="[^"]*"' | head -1 | tr -c '0-9' ' ')"; echo "$(( (x1+x2)/2 )) $(( (y1+y2)/2 ))"; }
mk_fg() { adb -s "$S" shell dumpsys window | grep mCurrentFocus | grep -q 'com.mknoon.app/'; }
case "$CMD" in
  texts)
    timeout 15 adb -s "$S" shell dumpsys window | grep mCurrentFocus
    X=$(dump); [ -z "$X" ] && { echo DUMP_FAILED; exit 4; }
    echo "$X" | grep -o -E '(content-desc|text)="[^"]{1,160}"' | grep -v '=""' ;;
  tap)
    L=$(dump | grep -F -- "$3" | head -1); [ -z "$L" ] && { echo "NOT FOUND: $3"; exit 3; }
    adb -s "$S" shell input tap $(center "$L"); echo "tapped $3" ;;
  shot)
    mk_fg || { echo "NOT MKNOON - no shot"; exit 3; }
    adb -s "$S" shell dumpsys window | grep -qE 'mCurrentFocus=.*(NotificationShade|Keyguard|StatusBar)' && { echo "shade/keyguard - no shot"; exit 3; }
    adb -s "$S" shell screencap -p /sdcard/s.png && adb -s "$S" pull /sdcard/s.png "$3" >/dev/null && adb -s "$S" shell rm -f /sdcard/s.png && echo "shot $3" ;;
  send)
    mk_fg || { echo "NOT MKNOON"; exit 3; }
    E=$(dump | grep 'android.widget.EditText' | head -1); [ -z "$E" ] && { echo "NO INPUT"; exit 4; }
    adb -s "$S" shell input tap $(center "$E"); sleep 1
    adb -s "$S" shell input text "$3"; sleep 1
    B=$(dump | grep 'content-desc="Send message"' | head -1); [ -z "$B" ] && { echo "NO SEND BUTTON"; exit 5; }
    adb -s "$S" shell input tap $(center "$B"); echo "SENT $(date -u +%FT%T.%3NZ)" ;;
  *) echo "usage"; exit 2 ;;
esac
