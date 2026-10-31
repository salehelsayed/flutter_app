#!/bin/bash
# Pixel screenshot via device file + pull (exec-out binary is mangled by the bridge). Only call with Mknoon verified in foreground.
#   px_shot.sh <out.png>
export ADB_SERVER_SOCKET=${ADB_SERVER_SOCKET:-tcp:host.docker.internal:5037}; S=${PX_SERIAL:-21071FDF600CSC}
top=$(timeout 20 adb -s $S shell dumpsys activity activities | grep -m1 topResumedActivity)
case "$top" in *com.mknoon.app*) ;; *) echo "REFUSED: Mknoon not in foreground"; exit 3;; esac
timeout 30 adb -s $S shell screencap -p /sdcard/px_shot.png && timeout 60 adb -s $S pull /sdcard/px_shot.png "$1" >/dev/null && timeout 20 adb -s $S shell rm /sdcard/px_shot.png && echo "saved $1"
