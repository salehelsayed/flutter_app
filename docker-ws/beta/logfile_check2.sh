#!/bin/bash
. "$(dirname "$0")/beta_env.sh"
RUN=$(current_run); F="$RUN/android_logcat_live.txt"
echo "app pid now: $($ADB shell pidof $PKG)"
echo "flutter lines: $(grep -c ' flutter ' "$F")   FLOW lines: $(grep -c '\[FLOW\]' "$F")   Mknoon native: $(grep -c 'Mknoon' "$F")"
echo "first/last line time: $(grep -m1 -oE '^[0-9-]+ [0-9:.]+' "$F") / $(tail -1 "$F" | grep -oE '^[0-9-]+ [0-9:.]+')"
grep -E ' flutter |Mknoon' "$F" | tail -5 | cut -c1-180
echo "--- emulator logcat buffer: FLOW lines since 21:29"
$ADB logcat -d -v time | awk '$2>="21:29:00"' | grep -c '\[FLOW\]'
