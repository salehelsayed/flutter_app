#!/bin/bash
# Stop leftover build processes by exact PID after a name and parent check:
#   dartvm whose parent is launchd (orphaned Flutter tool), xcodebuild whose parent is one of the listed dartvm PIDs,
#   xcodebuild orphaned from a stopped Appium (WebDriverAgent), or java whose arguments name GradleDaemon or KotlinCompileDaemon.
#   host-run bash docker-ws/kill_exact_orphan_build.sh <pid>...
set -u
ALL=" $* "
for PID in "$@"; do
  [[ "$PID" =~ ^[0-9]+$ ]] || { echo "refused: $PID"; continue; }
  NAME="$(ps -o comm= -p "$PID" 2>/dev/null)"; PARENT="$(ps -o ppid= -p "$PID" 2>/dev/null | tr -d ' ')"; ARGS="$(ps -o args= -p "$PID" 2>/dev/null)"
  ok=0
  case "${NAME##*/}" in
    dartvm) [ "$PARENT" = 1 ] && ok=1 ;;
    xcodebuild) case "$ALL" in *" $PARENT "*) ok=1 ;; esac
      [ "$PARENT" = 1 ] && case "$ARGS" in *appium-webdriveragent*|*WebDriverAgent*) ok=1 ;; esac ;;
    java) case "$ARGS" in *GradleDaemon*|*KotlinCompileDaemon*|*kotlin-daemon*) ok=1 ;; esac ;;
  esac
  [ "$ok" = 1 ] || { echo "refused: $PID (${NAME##*/}, parent $PARENT)"; continue; }
  kill "$PID" && echo "TERM $PID ${NAME##*/}"
done
sleep 5
for PID in "$@"; do ps -p "$PID" >/dev/null 2>&1 && echo "still running $PID"; done
echo done
