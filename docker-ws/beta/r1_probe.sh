#!/bin/bash
# Read-only: what the Pixel app did around the R1 kill/relaunch (current run's live logcat).
# Usage: r1_probe.sh <from HH:MM:SS> <to HH:MM:SS>
. "$(dirname "$0")/beta_env.sh"
RUN=$(current_run); L="$RUN/android_logcat_live.txt"
A=${1:-00:00:00}; B=${2:-23:59:59}
echo "log bytes: $(wc -c < "$L")"
awk -v a="$A" -v b="$B" 'substr($2,1,8)>=a && substr($2,1,8)<=b' "$L" \
  | grep -iE "Mknoon|CallsManager|addCall|Telecom|CALL_ANDROID|\"event\":\"CALL_|AndroidRuntime|FATAL|am_proc|Start proc [0-9]+:com.mknoon|has died|ActivityManager: Killing" \
  | grep -vE "GROUP|peer:ping|remoteIce|iceCandidate|TOKEN_PUBLISH" \
  | sed -E 's/^[0-9-]+ ([0-9:.]{12}) +([0-9]+) +([0-9]+) ([A-Z]) /\1 p\2 t\3 \4 /' | cut -c1-210 | head -${3:-60}
