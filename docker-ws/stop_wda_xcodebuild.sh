#!/bin/bash
# Stop one WebDriverAgent xcodebuild left by the private Appium server (port 4725) for a named iPhone after its session closed.
#   host-run bash docker-ws/stop_wda_xcodebuild.sh <pid> <udid>
PID="$1"; UDID="$2"
[[ "$PID" =~ ^[0-9]+$ ]] || { echo refused; exit 2; }
NAME="$(ps -o comm= -p "$PID")"; PARENT="$(ps -o ppid= -p "$PID" | tr -d ' ')"; ARGS="$(ps -o args= -p "$PID")"; PARGS="$(ps -o args= -p "$PARENT")"
case "${NAME##*/}" in xcodebuild) ;; *) echo "refused: not xcodebuild"; exit 3;; esac
case "$ARGS" in *WebDriverAgent*|*webdriveragent*) ;; *) echo "refused: not WDA"; exit 3;; esac
case "$ARGS" in *"$UDID"*) ;; *) echo "refused: udid not in args"; exit 3;; esac
case "$PARGS" in *appium*--port\ 4725*) ;; *) echo "refused: parent is not the private Appium"; exit 3;; esac
kill "$PID" && echo "TERM $PID WDA xcodebuild for $UDID"
