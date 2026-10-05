#!/bin/bash
# Stops this session's own Wave 3 check run for one check id (and its children).
check=$1
for p in $(pgrep -f "mknoon_checks.py run .*--only ${check}( |$)"); do
  echo "stopping $p: $(ps -o command= -p $p | cut -c1-160)"
  pkill -TERM -P "$p" 2>/dev/null; kill -TERM "$p"
done
