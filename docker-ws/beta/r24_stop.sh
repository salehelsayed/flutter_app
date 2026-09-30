#!/bin/bash
# Stop the R2-4 case runner and its Maestro sessions; KEEP the Pixel logcat capture running.
. "$(dirname "$0")/beta_env.sh"
RUN=$(current_run); TAG=$(basename "$RUN")
pkill -f "run_r24_validate.sh" && echo "runner stopped"
pkill -f "maestro --device .* $TAG" ; pkill -f "run_flow.sh .*D1[a-c]_" ; pkill -f "$TAG/maestro" && echo "maestro sessions stopped"
echo "[$(date '+%H:%M:%S')] R24 runner stopped by hand to inspect the real transcode stall (logcat capture kept)" >> "$RUN/timeline.txt"
ps -axo pid,command | grep -E "run_r24_validate|$TAG/maestro" | grep -v grep | cut -c1-120
