#!/bin/bash
# Stop orphaned flutter-build helpers whose cwd is the all-tests worktree, then delete the worktree
# DerivedData NotificationService intermediates (corrupt dependency_info.dat).
wt=/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree
pids=""
for p in $(pgrep -f "flutter_tools.snapshot"); do
  [ "$(ps -o ppid= -p $p | tr -d ' ')" = 1 ] || continue
  cwd=$(lsof -a -p $p -d cwd -Fn 2>/dev/null | sed -n 's/^n//p')
  [ "$cwd" = "$wt" ] && pids="$pids $p"
done
echo "stopping:$pids"; [ -n "$pids" ] && kill -TERM $pids; sleep 5
for p in $pids; do kill -0 $p 2>/dev/null && kill -KILL $p; done
pgrep -f "xcodebuild.*mknoon-all-tests-y227gs8x-worktree" && { echo "worktree xcodebuild still running; not deleting"; exit 3; }
d="$HOME/Library/Developer/Xcode/DerivedData/Runner-czaribshpwfsoocgfepptgzulnwh/Build/Intermediates.noindex/Runner.build/Debug-iphonesimulator/NotificationService.build"
[ -d "$d" ] && rm -rf "$d" && echo "removed $d"
