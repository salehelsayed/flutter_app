#!/bin/bash
# Plan 406: app process + crash check on both emulators.
ADBB=$HOME/Library/Android/sdk/platform-tools/adb
for S in emulator-5554 emulator-5556; do
  echo "$S pid=$($ADBB -s $S shell pidof com.mknoon.app | tr -d '\r') app_crashes=$($ADBB -s $S logcat -d -b crash 2>/dev/null | grep -c 'com.mknoon.app')"
done
