#!/bin/bash
# Stop the private Appium server (port 4725) by exact PID after checking its command line.
#   host-run bash docker-ws/stop_private_appium.sh <pid>
PID="$1"; [[ "$PID" =~ ^[0-9]+$ ]] || { echo refused; exit 2; }
ARGS="$(ps -o args= -p "$PID")"
case "$ARGS" in *appium*--port\ 4725*) ;; *) echo "refused: not the private Appium"; exit 3;; esac
kill "$PID" && echo "TERM $PID private Appium"
