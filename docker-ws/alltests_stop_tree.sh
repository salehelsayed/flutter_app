#!/bin/bash
# Stop the given root PIDs and all their descendants (SIGTERM, then SIGKILL after 20 s). Prints what it stopped.
desc() { local p=$1; echo $p; for c in $(pgrep -P $p); do desc $c; done; }
all=""; for r in "$@"; do all="$all $(desc $r)"; done
echo "== tree =="; for p in $all; do ps -o pid=,ppid=,etime=,command= -p $p 2>/dev/null | sed -E 's/--resolved_executable_name=[^ ]+ --executable_name=[^ ]+ //' | cut -c1-220; done
kill -TERM $all 2>/dev/null
for i in $(seq 1 20); do alive=""; for p in $all; do kill -0 $p 2>/dev/null && alive="$alive $p"; done; [ -z "$alive" ] && break; sleep 1; done
if [ -n "$alive" ]; then echo "SIGKILL:$alive"; kill -KILL $alive 2>/dev/null; sleep 1; fi
echo "== still alive =="; for p in $all; do kill -0 $p 2>/dev/null && echo $p; done; echo "== done =="
