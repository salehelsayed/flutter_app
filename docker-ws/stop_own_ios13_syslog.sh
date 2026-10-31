#!/bin/bash
# Stop one idevicesyslog capture of the iPhone 13 Runner process by exact PID after a name and args check.
#   host-run bash docker-ws/stop_own_ios13_syslog.sh <pid>
PID="$1"; [[ "$PID" =~ ^[0-9]+$ ]] || { echo refused; exit 2; }
NAME="$(ps -o comm= -p "$PID")"; ARGS="$(ps -o args= -p "$PID")"
case "${NAME##*/}" in idevicesyslog) ;; *) echo "refused: not idevicesyslog"; exit 3;; esac
case "$ARGS" in *"-u 00008110-00184D622289801E --process Runner"*) ;; *) echo "refused: args"; exit 3;; esac
kill "$PID" && echo "TERM $PID idevicesyslog iPhone 13"
