#!/bin/bash
# Usage: pixel_motion_probe.sh <serial> <out.mp4> <gesture-cmd...>; records 6 s of the screen (only with Mknoon in front) while running the gesture after 1.5 s.
S="$1"; O="$2"; shift 2
adb -s "$S" shell dumpsys window | grep mCurrentFocus | grep -q 'com.mknoon.app/' || { echo "NOT MKNOON FOREGROUND"; exit 3; }
adb -s "$S" shell screenrecord --time-limit 9 --bit-rate 8000000 /sdcard/motion.mp4 &
RP=$!; sleep 1.0; "$@"; wait $RP
adb -s "$S" pull /sdcard/motion.mp4 "$O" | tail -1; adb -s "$S" shell rm -f /sdcard/motion.mp4
