#!/bin/bash
# Read-only: call transitions/results from the fixed run's Android capture
# (optionally only lines at/after HH:MM given as $1).
. "$(dirname "$0")/beta_env.sh"
RUN=$(current_run)
grep -E '"event":"CALL_(STATE_TRANSITION|CONTROL_SIGNAL_SEND_(RESULT|FAILED)|TERMINAL_CLEANUP_RESULT|MEDIA_CLOSE)' "$RUN/android_logcat_live.txt" \
  | grep -vE 'remoteIce|iceCandidateHandled' \
  | awk -v from="${1:-00:00}" '$2 >= from' \
  | sed -E 's/^[0-9-]+ ([0-9:.]{12}).*"event":"/\1 /; s/","details":/ /' | cut -c1-170 | tail -n ${2:-40}
