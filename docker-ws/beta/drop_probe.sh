#!/bin/bash
# Read-only: every call_signal routed on the Pixel since $1, and the next call event after it.
. "$(dirname "$0")/beta_env.sh"
RUN=$(current_run)
awk -v a="$1" '$2>=a' "$RUN/android_logcat_live.txt" | grep -E 'MESSAGE_ROUTER_ROUTING.*call_signal|"event":"CALL_(STATE_TRANSITION|INCOMING[A-Z_]*|SIGNAL[A-Z_]*_(REJECT|DROP|IGNOR|FAIL)[A-Z_]*)"|call_signal' \
 | grep -vE 'remoteIce|iceCandidate' | sed -E 's/.*"ts":"[0-9-]+T([0-9:.]{12})[^"]*".*"event":"/\1 /; s/","details":/ /' | cut -c1-170 | head -30
