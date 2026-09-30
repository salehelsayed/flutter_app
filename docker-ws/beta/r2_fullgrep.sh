#!/bin/bash
# Read-only: full (untrimmed) live-logcat lines matching a regex, first N.
. "$(dirname "$0")/beta_env.sh"
RUN=$(current_run); grep -E "$1" "$RUN/android_logcat_live.txt" | head -${2:-5} | sed -E "s/.*\"event\":/\"event\":/" | cut -c1-700
