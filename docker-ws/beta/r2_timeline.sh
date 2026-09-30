#!/bin/bash
# Read-only: the current run's full timeline + whether the runner is alive.
. "$(dirname "$0")/beta_env.sh"
cat "$(current_run)/timeline.txt" 2>/dev/null
pgrep -f run_round2.sh >/dev/null && echo "#ALIVE" || echo "#DEAD"
