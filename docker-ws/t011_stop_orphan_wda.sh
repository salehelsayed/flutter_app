#!/bin/bash
# Stop ONE orphaned (ppid 1) WebDriverAgent xcodebuild for the iPhone 11 left after the T011 private Appium (4725) shut down.
#   host-run bash docker-ws/t011_stop_orphan_wda.sh <pid>
PID="$1"; UDID=00008030-001A6D2801BB802E
[[ "$PID" =~ ^[0-9]+$ ]] || { echo refused; exit 2; }
NAME="$(ps -o comm= -p "$PID")"; PARENT="$(ps -o ppid= -p "$PID" | tr -d ' ')"; ARGS="$(ps -o args= -p "$PID")"
case "${NAME##*/}" in xcodebuild) ;; *) echo "refused: not xcodebuild"; exit 3;; esac
case "$ARGS" in *WebDriverAgent*) ;; *) echo "refused: not WDA"; exit 3;; esac
case "$ARGS" in *"$UDID"*) ;; *) echo "refused: not the iPhone 11"; exit 3;; esac
[ "$PARENT" = 1 ] || { echo "refused: not orphaned"; exit 3; }
kill "$PID" && echo "TERM $PID"
