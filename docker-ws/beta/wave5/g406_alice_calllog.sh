#!/bin/bash
# AliceH call flow events from the last call attempt (logcat).
/Users/I560101/Library/Android/sdk/platform-tools/adb -s emulator-5554 logcat -d | grep -oE '"event":"CALL_[A-Z_]+"[^}]{0,160}' | tail -25
