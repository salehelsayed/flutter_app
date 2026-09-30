#!/bin/bash
# Read-only: is run_full4.sh alive, the last timeline lines, and the Mac load.
. "$(dirname "$0")/beta_env.sh"
echo "runner alive: $(pgrep -f run_full4.sh >/dev/null && echo yes || echo no)  load: $(sysctl -n vm.loadavg)"
RUN=$(current_run 2>/dev/null); [ -n "$RUN" ] && { echo "RUN=$RUN"; tail -n ${1:-40} "$RUN/timeline.txt"; }
tail -5 "$(dirname "$0")/run_full4.out" 2>/dev/null
