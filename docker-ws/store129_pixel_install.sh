#!/bin/bash
# Pixel 6 only: install one APK with install -r (pass -d as 2nd arg to allow downgrade), then print its version.
export PATH="$HOME/Library/Android/sdk/platform-tools:$PATH"
S=21071FDF600CSC; adb -s $S install -r ${2:-} "${1:?apk}" 2>&1 | tail -2
adb -s $S shell dumpsys package com.mknoon.app | grep -E 'versionName|versionCode|pkgFlags' | head -3
