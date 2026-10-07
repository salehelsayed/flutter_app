#!/bin/bash
# Stop a leftover Maestro on-device driver (our own, from a stopped run) on the given Android serial.
export PATH="$HOME/Library/Android/sdk/platform-tools:$PATH"
S=$1
adb -s "$S" shell am force-stop dev.mobile.maestro.test 2>/dev/null
adb -s "$S" shell am force-stop dev.mobile.maestro 2>/dev/null
sleep 2
adb -s "$S" shell ps -A | grep -iE "maestro" || echo "no maestro process on $S"
adb -s "$S" shell dumpsys activity processes | grep -ciE "instrumentation|activeInstr" 
