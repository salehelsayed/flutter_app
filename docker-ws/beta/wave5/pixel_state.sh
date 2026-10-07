#!/bin/bash
export PATH="$HOME/Library/Android/sdk/platform-tools:$PATH"; S=21071FDF600CSC
echo "awake: $(adb -s $S shell dumpsys power | grep -m1 -oE 'mWakefulness=[A-Za-z]+')"
echo "keyguard: $(adb -s $S shell dumpsys window | grep -m1 -oE 'mDreamingLockscreen=[a-z]+|isKeyguardShowing=[a-z]+|mShowingLockscreen=[a-z]+')"
adb -s $S shell ps -A | grep -E "maestro|uiautomator" | head -3 || true
