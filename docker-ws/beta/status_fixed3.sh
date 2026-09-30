#!/bin/bash
. "$(dirname "$0")/beta_env.sh"
echo "runner alive: $(pgrep -f run_fixed3.sh >/dev/null && echo yes || echo no)"
RUN=$(current_run 2>/dev/null); [ -n "$RUN" ] && tail -n ${1:-40} "$RUN/timeline.txt"
tail -5 "$(dirname "$0")/run_fixed3.out" 2>/dev/null
