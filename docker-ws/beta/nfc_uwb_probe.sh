#!/bin/bash
# Probe (and optionally quiet) the crash-looping NFC app and UWB HAL on emulator-5556.
# Usage: nfc_uwb_probe.sh [quiet]   -- "quiet" tries reversible user-level disables.
. "$(dirname "$0")/beta_env.sh"
echo "--- packages"
$ADB shell pm list packages 2>/dev/null | grep -iE "nfc|uwb" | tr '\n' ' '; echo
echo "--- uwb commands"
$ADB shell cmd uwb help 2>&1 | head -12
echo "--- settings"
$ADB shell 'settings get global uwb_enabled; settings get global nfc_on 2>/dev/null' | tr '\n' ' '; echo
if [ "${1:-}" = "quiet" ]; then
  echo "--- disabling (reversible: pm enable / cmd uwb enable-uwb)"
  $ADB shell pm disable-user --user 0 com.google.android.nfc 2>&1 | head -2
  $ADB shell cmd uwb disable-uwb 2>&1 | head -2
  $ADB shell settings put global uwb_enabled 0 2>&1 | head -2
fi
echo "--- crash counts in the last 3000 log lines"
$ADB logcat -d -t 3000 2>/dev/null | grep -oE "Fatal signal 6|com.google.android.nfc .*has died|Loading C NFC Support" | sed -E 's/\(pid [0-9]+\) //' | sort | uniq -c
