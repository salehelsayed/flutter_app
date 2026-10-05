#!/bin/bash
# Stop one of this session's own mknoon_checks runs by pid, with its whole process tree.
p=$1
ps -o command= -p "$p" | grep -q "scripts/mknoon_checks.py run" || { echo "pid $p is not a checks run"; exit 1; }
kids() { for c in $(pgrep -P "$1"); do kids "$c"; echo "$c"; done; }
all="$(kids "$p") $p"
kill -TERM $all 2>/dev/null; sleep 3; kill -KILL $all 2>/dev/null
echo "stopped: $all"
