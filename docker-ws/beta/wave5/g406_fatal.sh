#!/bin/bash
# Plan 406: show the FATAL/SIGABRT/session-ticket logcat lines on an emulator.
ADBB=$HOME/Library/Android/sdk/platform-tools/adb
S=${1:-emulator-5556}
$ADBB -s $S logcat -d | grep -E 'FATAL|SIGABRT|session ticket' | cut -c1-260 | head -14
echo "--- app pid now: $($ADBB -s $S shell pidof com.mknoon.app)"
