#!/bin/bash
# Starts continuous log capture for a new run dir (detached from the bridge).
# Usage: logs_start.sh            -> creates run-<stamp>, writes current_run.txt
. "$(dirname "$0")/beta_env.sh"
RUN="$BETA/run-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$RUN/screens" "$RUN/maestro"
echo "$RUN" > "$BETA/current_run.txt"
nohup $ADB logcat -v threadtime > "$RUN/android_logcat.txt" 2>&1 &
echo $! > "$RUN/logcat.pid"
# iOS: detached `log stream` writes nothing, so logs_stop.sh exports the whole
# window with `log show --start` instead.
date '+%Y-%m-%d %H:%M:%S' > "$RUN/ios_log_start.txt"
cp "$BETA/build/build_name.txt" "$BETA/build/provenance.txt" "$RUN/" 2>/dev/null
echo "RUN=$RUN"
