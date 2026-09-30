#!/bin/bash
# Read-only: is run_round2.sh alive, the last timeline lines, and the Mac load.
. "$(dirname "$0")/beta_env.sh"
echo "runner alive: $(pgrep -f run_round2.sh >/dev/null && echo yes || echo no)  load: $(sysctl -n vm.loadavg)  now: $(date '+%H:%M:%S')"
RUN=$(current_run 2>/dev/null); [ -n "$RUN" ] && { echo "RUN=$RUN"; tail -n ${1:-30} "$RUN/timeline.txt"; }
tail -3 "$(dirname "$0")/run_round2.out" 2>/dev/null
