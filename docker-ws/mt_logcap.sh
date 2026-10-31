#!/bin/bash
# Onboarding discovery proof: Pixel logcat capture from app launch, start|stop <name>.
S=21071FDF600CSC; E=/Volumes/CrucialX9/flutter_app/.codex-test-logs/move-terminal-20261024T0029Z
case "$1" in
  start) adb -s $S logcat -c; nohup adb -s $S logcat -v epoch > "$E/$2.logcat" 2>/dev/null < /dev/null & echo $! > "$E/$2.pid"; echo "capturing pid $(cat "$E/$2.pid")" ;;
  stop) P=$(cat "$E/$2.pid"); case "$(ps -o args= -p "$P")" in *"adb -s $S logcat"*) kill "$P" && echo "stopped $P";; *) echo "refused";; esac; wc -l < "$E/$2.logcat" ;;
esac
