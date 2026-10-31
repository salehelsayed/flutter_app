#!/bin/bash
# Stop one mknoon_checks.py run by exact PID after a name check, plus its direct children.
P="$1"
args=$(ps -o args= -p "$P" 2>/dev/null)
case "$args" in *scripts/mknoon_checks.py*) ;; *) echo "refused: pid $P is not mknoon_checks.py ($args)"; exit 2;; esac
kids=$(pgrep -P "$P")
echo "children: ${kids:-none}"
for k in $kids; do kill "$k" 2>/dev/null; done
kill "$P" && echo "stopped $P"
