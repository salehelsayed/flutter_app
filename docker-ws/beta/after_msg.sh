#!/bin/bash
. "$(dirname "$0")/beta_env.sh"
RUN=$(current_run)
awk '$2>="22:19:52.9" && $2<="22:20:08"' "$RUN/android_logcat_live.txt" | grep -E '\[FLOW\]|Mknoon|CHAT_TRANSPORT' \
 | grep -vE 'BRIDGE_CALL_TIMING|peer:ping|ID_REPO|GROUP' \
 | sed -E 's/.*"ts":"[0-9-]+T([0-9:.]{12})[^"]*".*"event":"/\1 /; s/","details":/ /' | cut -c1-190 | head -40
