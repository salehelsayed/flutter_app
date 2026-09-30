#!/bin/bash
# grep a run file ON THE MAC (the container's view of the mount lags minutes).
# Usage: mac_grep.sh <file relative to run dir> <extended regex> [max lines] [out-file]
. "$(dirname "$0")/beta_env.sh"
RUN=$(current_run)
if [ -n "${4:-}" ]; then
  grep -E "$2" "$RUN/$1" > "$RUN/$4"; wc -l "$RUN/$4"
else
  grep -E "$2" "$RUN/$1" | head -n "${3:-200}"
fi
