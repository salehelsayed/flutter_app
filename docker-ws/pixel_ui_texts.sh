#!/bin/bash
# Usage: pixel_ui_texts.sh <serial>; prints non-empty text/content-desc of the current screen and focused window.
S="$1"
adb -s "$S" shell dumpsys window | grep mCurrentFocus
adb -s "$S" shell uiautomator dump /sdcard/u.xml >/dev/null 2>&1
adb -s "$S" shell cat /sdcard/u.xml | tr '>' '\n' | grep -o -E '(content-desc|text)="[^"]{1,80}"' | grep -v '=""'
