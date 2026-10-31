#!/bin/bash
# Read-only: list processes whose command name matches exactly one of the given names.
#   host-run bash docker-ws/list_named_procs.sh <name>...
for N in "$@"; do
  for P in $(pgrep -x "$N" 2>/dev/null); do ps -o pid=,ppid=,etime=,rss=,args= -p "$P" | cut -c1-220; done
done
