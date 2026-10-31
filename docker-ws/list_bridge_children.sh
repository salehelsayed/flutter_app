#!/bin/bash
# Read-only: list direct children of the given bridge PID (pid, etime, comm, args cut).
#   host-run bash docker-ws/list_bridge_children.sh <bridge-pid>
B="${1:?bridge pid}"; [[ "$B" =~ ^[0-9]+$ ]] || exit 2
ps -axo pid=,ppid=,etime=,comm=,args= | awk -v b="$B" '$2==b' | cut -c1-200
