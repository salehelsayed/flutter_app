#!/bin/bash
# Read-only: size/liveness of the current run's Android capture.
. "$(dirname "$0")/beta_env.sh"
RUN=$(current_run); echo "run: $RUN"
ls -la "$RUN"/android_logcat*.txt
echo "logcat pid $(cat "$RUN/logcat.pid") alive: $(ps -p "$(cat "$RUN/logcat.pid")" >/dev/null && echo yes || echo no)"
tail -2 "$RUN/android_logcat_live.txt" | cut -c1-140
grep -c '"event":"CALL_STATE_TRANSITION' "$RUN/android_logcat_live.txt"
