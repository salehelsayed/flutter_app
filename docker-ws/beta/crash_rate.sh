#!/bin/bash
# Read-only: timestamps of the latest native crashes / NFC restarts on emulator-5556.
. "$(dirname "$0")/beta_env.sh"
echo "emu now: $($ADB shell date '+%H:%M:%S')"
$ADB logcat -d -t 4000 -v time 2>/dev/null | GRAPH_OK=1 grep -E "Fatal signal 6|nfc.*has died|NativeNfcManager|uwb" | tail -6 | cut -c1-160
$ADB shell cmd uwb status 2>&1 | head -3
