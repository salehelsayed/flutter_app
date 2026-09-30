#!/bin/bash
# Read-only: the current run's timeline as the Mac sees it, and whether the runner is alive.
. "$(dirname "$0")/beta_env.sh"
RUN=$(current_run); echo "run $RUN"; cut -c1-300 "$RUN/timeline.txt"
pgrep -f run_r24_validate.sh >/dev/null && echo "#R24_ALIVE" || echo "#R24_DEAD"
