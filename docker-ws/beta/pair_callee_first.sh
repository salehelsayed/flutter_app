#!/bin/bash
# Like pair.sh, but for calls where the Pixel is the callee: start the Android
# flow first, wait until Maestro's Android driver is actually looking at the
# screen (a "Maestro : Requesting view hierarchy" line newer than the start in
# the live logcat), and only then start the iOS caller flow. On this Mac the
# Android driver can take a minute to start, while the iPhone places its call
# within seconds, so starting both at once let the call ring out first.
# Usage: pair_callee_first.sh <label> <ios-flow> <android-flow> [KEY=VAL ...]
H="$(dirname "$0")"
. "$H/beta_env.sh"
RUN=$(current_run)
LABEL=$1; IF=$2; AF=$3; shift 3
start=$($ADB shell date "'+%m-%d %H:%M:%S'" | tr -d '\r')
bash "$H/run_flow.sh" android "$AF" "$LABEL" "$@" &
A=$!
ready=0
for i in $(seq 1 240); do
  if tail -c 3000000 "$RUN/android_logcat_live.txt" | grep -E " Maestro *: Requesting view hierarchy" \
       | awk -v s="$start" '($1 " " $2) >= s' | grep -q .; then ready=1; break; fi
  kill -0 $A 2>/dev/null || break
  sleep 1
done
echo "[$(date '+%H:%M:%S')] $LABEL callee maestro $([ $ready = 1 ] && echo ready || echo NOT ready) after ${i}s" >> "$RUN/timeline.txt"
bash "$H/run_flow.sh" ios "$IF" "$LABEL" "$@" &
wait
