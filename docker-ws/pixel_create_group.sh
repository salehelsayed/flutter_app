#!/bin/bash
# Usage: pixel_create_group.sh <serial> <name>; from a group chat or Orbit, creates a group with the first contact row ("iphone").
S="$1"; N="$2"; t() { adb -s "$S" shell input tap "$1" "$2"; sleep "${3:-2}"; }
adb -s "$S" shell dumpsys window | grep mCurrentFocus | grep -q 'com.mknoon.app/' || { echo "NOT MKNOON"; exit 3; }
adb -s "$S" shell input keyevent 4; sleep 3
t 985 201; t 864 340 3
adb -s "$S" shell uiautomator dump /sdcard/u.xml >/dev/null 2>&1
adb -s "$S" shell cat /sdcard/u.xml | tr '>' '\n' | grep -q 'content-desc="iphone&#10;' || { echo "NO iphone row"; exit 4; }
t 1011 535; t 540 2070 1
adb -s "$S" shell input text "$N"; sleep 1; adb -s "$S" shell input keyevent 111; sleep 1
t 540 2230 5
adb -s "$S" shell uiautomator dump /sdcard/u.xml >/dev/null 2>&1
adb -s "$S" shell cat /sdcard/u.xml | tr '>' '\n' | grep -q "content-desc=\"$N\"" && echo "CREATED $N" || { echo "NOT CONFIRMED $N"; exit 5; }
