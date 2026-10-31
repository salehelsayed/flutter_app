#!/bin/bash
# Read-only: 1 s stack sample and open lock/log files of one exact PID (macOS sample + lsof).
#   host-run bash docker-ws/pid_stack.sh <pid>
P="${1:?pid}"; [[ "$P" =~ ^[0-9]+$ ]] || exit 2
ps -o comm= -p "$P" | grep -q Python || { echo "not a Python pid"; exit 3; }
/usr/sbin/lsof -p "$P" 2>/dev/null | awk '{print $4, $NF}' | grep -E 'lock|\.log|\.json|sock|FIFO|PIPE' | head -20
/usr/bin/sample "$P" 1 -mayDie 2>/dev/null | grep -E 'flock|select|poll|sleep|wait|read|lock' | head -15
