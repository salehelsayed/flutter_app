#!/bin/bash
# Read-only: what is using CPU inside emulator-5556, and crash-looping services.
. "$(dirname "$0")/beta_env.sh"
t0=$(date +%s)
$ADB shell 'uptime; top -b -n 1 -m 18 -o PID,USER,%CPU,S,TIME+,ARGS' 2>&1 | head -30 | cut -c1-150
echo "(adb took $(( $(date +%s) - t0 )) s)"
echo "--- crash/restart counts in the last 5000 log lines"
$ADB logcat -d -t 5000 2>/dev/null | grep -oE "Loading C NFC Support|android.hardware.uwb|Fatal signal [0-9]+|ANR in [a-z.]+|WATCHDOG" | sort | uniq -c | sort -rn | head
echo "--- nfc/uwb state"
$ADB shell 'svc nfc 2>&1 | head -3; settings get global nfc_on 2>/dev/null; cmd uwb get-uwb-enabled-state 2>&1 | head -2; getprop init.svc.vendor.uwb_hal 2>/dev/null; getprop | grep -iE "init.svc.*(nfc|uwb)" | head'
