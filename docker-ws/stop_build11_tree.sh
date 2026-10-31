#!/bin/bash
# List (no args) or stop (exact PIDs) this session's build-11 lease wrapper and its descendants.
#   host-run bash docker-ws/stop_build11_tree.sh [pid...]
TAG='build-11-lease.log'
if [ $# -eq 0 ]; then
  for W in $(ps -axo pid=,args= | grep -F "$TAG" | grep -v grep | awk '{print $1}'); do
    echo "wrapper $W"; Q="$W"
    while [ -n "$Q" ]; do N=""; for P in $Q; do for C in $(pgrep -P "$P"); do ps -o pid=,args= -p "$C" | cut -c1-140; N="$N $C"; done; done; Q="$N"; done
  done; exit 0
fi
for P in "$@"; do [[ "$P" =~ ^[0-9]+$ ]] && kill -TERM "$P" && echo "TERM $P"; done
