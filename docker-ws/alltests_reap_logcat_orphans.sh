#!/bin/bash
# Kill orphaned (ppid 1) adb logcat streams whose cwd is the all-tests worktree (leaked by run harnesses).
wt=/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree; hit=""
for p in $(pgrep -f "adb .*logcat"); do
  [ "$(ps -o ppid= -p $p | tr -d ' ')" = 1 ] || continue
  cwd=$(lsof -a -p $p -d cwd -Fn 2>/dev/null | sed -n 's/^n//p'); [ "$cwd" = "$wt" ] || continue
  hit="$hit $p"
done
[ -z "$hit" ] && { echo "no worktree logcat orphans"; exit 0; }
ps -o pid=,etime=,command= -p $(echo $hit | tr ' ' ',') | cut -c1-160
kill -TERM $hit 2>/dev/null; sleep 2; echo "reaped:$hit"
