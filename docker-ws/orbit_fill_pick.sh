#!/bin/bash
# In the Android DocumentsUI picker (list view, files visible), select several files by exact name, then tap Select.
# First file: long press (starts multi-select); others: tap. One file only: plain tap.
#   orbit_fill_pick.sh <serial> <file> [file ...]
export ADB_SERVER_SOCKET=${ADB_SERVER_SOCKET:-tcp:host.docker.internal:5037}
S="$1"; shift; N=$#; i=0
xy() {
  adb -s "$S" shell rm -f /sdcard/u.xml; adb -s "$S" shell uiautomator dump /sdcard/u.xml >/dev/null 2>&1
  L=$(adb -s "$S" shell cat /sdcard/u.xml | tr '>' '\n' | grep -F "$1" | head -1)
  [ -z "$L" ] && return 1
  read -r x1 y1 x2 y2 <<<"$(echo "$L" | grep -o 'bounds="[^"]*"' | tr -c '0-9' ' ')"; echo "$(( (x1+x2)/2 )) $(( (y1+y2)/2 ))"
}
for f in "$@"; do
  P=""
  for sw in 0 d d d d u u u u u u u u; do
    case $sw in d) adb -s "$S" shell input swipe 540 1700 540 1100 600; sleep 1.5;; u) adb -s "$S" shell input swipe 540 1000 540 1600 600; sleep 1.5;; esac
    P=$(xy "text=\"$f\"") || continue
    read -r x y <<<"$P"; [ "$y" -lt 400 ] && { P=""; continue; }; [ "$y" -gt 2150 ] && { P=""; continue; }
    break
  done
  [ -z "$P" ] && { echo "NOT FOUND $f"; exit 3; }
  read -r x y <<<"$P"
  if [ $N -gt 1 ] && [ $i -eq 0 ]; then adb -s "$S" shell input swipe $x $y $x $y 900; else adb -s "$S" shell input tap $x $y; fi
  i=$((i+1)); sleep 1.5
done
if [ $N -gt 1 ]; then
  P=$(xy 'text="Select"') || P=$(xy 'text="SELECT"') || { echo "NO SELECT BUTTON"; exit 4; }
  adb -s "$S" shell input tap $P
fi
echo "picked $N"
