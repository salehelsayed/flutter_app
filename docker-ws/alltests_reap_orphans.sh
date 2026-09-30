#!/bin/bash
# Kill orphaned (ppid 1) flutter_tools processes whose cwd is the all-tests worktree, but ONLY when no
# non-orphaned flutter_tools build for that worktree is still running (so a live build is never touched).
wt=/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree; live=0; orphans=""
for p in $(pgrep -f "flutter_tools.snapshot"); do
  cwd=$(lsof -a -p $p -d cwd -Fn 2>/dev/null | sed -n 's/^n//p'); [ "$cwd" = "$wt" ] || continue
  if [ "$(ps -o ppid= -p $p | tr -d ' ')" = 1 ]; then orphans="$orphans $p"; else live=1; fi
done
if [ "$live" = 1 ]; then echo "live build running; skip"; exit 0; fi
[ -z "$orphans" ] && { echo "no orphans"; exit 0; }
kill -TERM $orphans 2>/dev/null; sleep 3; for p in $orphans; do kill -0 $p 2>/dev/null && kill -KILL $p; done
echo "reaped:$orphans"
