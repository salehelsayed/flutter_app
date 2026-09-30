#!/bin/bash
# Remove the finished watcher's leftover log stream (adb logcat + grep orphans); prints what is left.
. "$(dirname "$0")/beta_env.sh"
pkill -f "grep --line-buffered -E appium" && echo "watch grep stopped"
for p in $(pgrep -f "adb -s $SERIAL logcat -T 1 -v threadtime"); do
  [ "$(ps -o ppid= -p "$p" | tr -d ' ')" = 1 ] && kill "$p" && echo "orphan logcat $p stopped"
done
ps -axo pid,ppid,command | grep -E "logcat -T 1|grep --line-buffered" | grep -v grep | cut -c1-150
