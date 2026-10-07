#!/bin/bash
# Read-only: foreground app on each Android device and booted simulators' foreground state.
export PATH="$HOME/Library/Android/sdk/platform-tools:$PATH"
for s in 21071FDF600CSC emulator-5554 emulator-5556 emulator-5558; do
  echo "$s: $(adb -s $s shell dumpsys activity activities 2>/dev/null | grep -m1 -E 'topResumedActivity|mResumedActivity' | grep -oE '[a-z0-9_.]+/[A-Za-z0-9_.]+' | head -1) screen=$(adb -s $s shell dumpsys power 2>/dev/null | grep -m1 -oE 'mWakefulness=[A-Za-z]+')"
done
