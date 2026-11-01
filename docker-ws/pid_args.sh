#!/bin/bash
# Read-only: show pid, parent pid, age and the first 160 chars of the command line for the given PIDs.
#   host-run bash docker-ws/pid_args.sh <pid>...
for p in "$@"; do ps -o pid=,ppid=,etime=,args= -p "$p" 2>/dev/null | cut -c1-200 || echo "$p gone"; done
