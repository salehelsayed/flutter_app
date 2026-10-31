#!/bin/bash
# Pixel: tap a point only while Mknoon is focused, then print screen texts.
export PATH="$HOME/Library/Android/sdk/platform-tools:$PATH"; S=21071FDF600CSC
adb -s $S shell dumpsys window | grep -q "mCurrentFocus=.*com.mknoon.app/" || { echo "NOT FOREGROUND"; exit 3; }
adb -s $S shell input tap "$1" "$2"; sleep 4; bash "$(dirname "$0")/pixel_ui_texts.sh" $S | head -${3:-10}
