#!/bin/bash
# Read-only Pixel/emulator state: attached devices, Mknoon versions, battery, foreground window.
export PATH="$HOME/Library/Android/sdk/platform-tools:$PATH"
adb devices -l
for s in $(adb devices | awk 'NR>1 && $2=="device"{print $1}'); do
  echo "== $s"; adb -s "$s" shell dumpsys package com.mknoon.app 2>/dev/null | grep -E 'versionName|versionCode|lastUpdateTime' | head -3
  adb -s "$s" shell pm list packages 2>/dev/null | grep -i mknoon | tr -d '\r' | tr '\n' ' '; echo
  adb -s "$s" shell dumpsys battery | grep -E 'level' | head -1
  adb -s "$s" shell dumpsys window 2>/dev/null | grep -E 'mCurrentFocus' | head -1
done
