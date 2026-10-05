#!/bin/bash
# Stop idle orphaned `flutter build ios` helpers (ppid 1, cwd = the wave3-next worktree) that keep a finished
# build's output pipe open, so the waiting SIMS process sees end-of-output.
WT=/Volumes/CrucialX9/flutter_app/.claude/worktrees/wave3-next
n=0
for p in $(ps -axo pid=,ppid=,command= | awk '$2==1 && /dartvm/ && /build ios/ {print $1}'); do
  cwd=$(lsof -a -p "$p" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p')
  case "$cwd" in ("$WT"*) kill -KILL "$p" 2>/dev/null && n=$((n+1));; esac
done
echo "stopped $n orphaned build helpers"
