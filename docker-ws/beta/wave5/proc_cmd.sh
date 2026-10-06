#!/bin/bash
# Read-only: full command line, parent, state and open-file summary of the given pids.
for p in "$@"; do echo "== $p"; ps -o pid=,ppid=,stat=,etime=,command= -p "$p" | cut -c1-1200; done
