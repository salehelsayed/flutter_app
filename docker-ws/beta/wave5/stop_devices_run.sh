#!/bin/bash
# Stop the Wave 5 full run and every process it started whose cwd is the wave3-next worktree.
WT=/Volumes/CrucialX9/flutter_app/.claude/worktrees/wave3-next
for p in $(pgrep -f "mknoon_checks.py full"); do kill -TERM "$p" 2>/dev/null && echo "TERM runner $p"; done
pkill -TERM -f "docker-ws/beta/wave5/devices_run.sh" 2>/dev/null
sleep 8
n=0
for p in $(ps -axo pid=,command= | awk '/flutter|dart|xcodebuild|gradle|go test|python3|maestro/ {print $1}'); do
  cwd=$(lsof -a -p "$p" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p')
  case "$cwd" in ("$WT"*) kill -KILL "$p" 2>/dev/null && n=$((n+1));; esac
done
echo "killed $n leftover worktree processes"; pgrep -fl "mknoon_checks.py full" || echo "runner gone"
