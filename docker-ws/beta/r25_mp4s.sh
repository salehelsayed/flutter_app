#!/bin/bash
# Read-only: every mp4 in the app's private and external dirs, with size and time (to find transcoder outputs).
. "$(dirname "$0")/beta_env.sh"
$ADB shell "run-as $PKG sh -c 'ls -la --time-style=+%H:%M:%S \$(find /data/user/0/$PKG /sdcard/Android/data/$PKG -name \"*.mp4\" 2>/dev/null) 2>/dev/null'" | tr -d '\r' | awk '{print $6, $5, $7}' | sort | tail -20
echo "--- external dir listing"
$ADB shell "run-as $PKG ls -la /sdcard/Android/data/$PKG/files/ /sdcard/Android/data/$PKG/files/video_compress 2>&1" | tr -d '\r' | head -12
$ADB shell "ls -la /sdcard/Android/data/$PKG/files/video_compress 2>&1" | tr -d '\r' | head -8
