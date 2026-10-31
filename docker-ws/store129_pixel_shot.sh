#!/bin/bash
# Pixel: screenshot only when Mknoon is the focused window. <out-png on host>
export PATH="$HOME/Library/Android/sdk/platform-tools:$PATH"; S=21071FDF600CSC
adb -s $S shell dumpsys window | grep -q "mCurrentFocus=.*com.mknoon.app/" || { echo "NOT FOREGROUND"; exit 3; }
adb -s $S shell screencap -p /sdcard/q129.png && adb -s $S pull /sdcard/q129.png "${1:?out}" >/dev/null && adb -s $S shell rm /sdcard/q129.png; echo saved
