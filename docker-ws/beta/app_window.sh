#!/bin/bash
# Read-only: all lines of the app pid in a time window of the current run's logcat.
# Usage: app_window.sh <HH:MM:SS start> <HH:MM:SS end> <out label>
. "$(dirname "$0")/beta_env.sh"
RUN=$(current_run); mkdir -p "$RUN/windows"
PID=$(awk -v s="$1" '$2>=s && / flutter *:/ {print $3; exit}' "$RUN/android_logcat_live.txt")
awk -v s="$1" -v e="$2" -v p="$PID" '$2>=s && $2<=e && $3==p' "$RUN/android_logcat_live.txt" > "$RUN/windows/$3_pixel_app.txt"
wc -l "$RUN/windows/$3_pixel_app.txt"; echo "pid $PID"
