#!/bin/bash
# Read-only: cumulative CPU time and state of the given pids, sampled twice 15 s apart.
ps -o pid=,stat=,time=,etime=,comm= -p "$(echo "$@" | tr ' ' ',')"; sleep 15; ps -o pid=,stat=,time=,etime=,comm= -p "$(echo "$@" | tr ' ' ',')"
