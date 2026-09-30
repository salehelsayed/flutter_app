#!/bin/bash
# Read-only: the current run's timeline + whether the re-run driver is alive.
. "$(dirname "$0")/beta_env.sh"
cat "$(current_run)/timeline.txt" 2>/dev/null
pgrep -f run_round2_rerun.sh >/dev/null && echo "#ALIVE" || echo "#DEAD"
