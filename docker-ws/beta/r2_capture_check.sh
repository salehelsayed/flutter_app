#!/bin/bash
# Read-only: is the current run's live logcat growing, and does it hold app lines?
. "$(dirname "$0")/beta_env.sh"
RUN=$(current_run); L="$RUN/android_logcat_live.txt"
echo "run: $RUN"; ls -la "$L" | awk '{print $5, $6, $7, $8}'
echo "flutter lines: $(grep -c ' flutter ' "$L")  overflow lines: $(grep -c -i 'overflow' "$L")"
grep -i -m3 'overflow' "$L" | cut -c1-200
echo "capture pids: $(pgrep -f 'logcat -T 1 -v threadtime' | tr '\n' ' ')"
tail -2 "$L" | cut -c1-150
