#!/bin/bash
# Stop this session's hung worktree builds: the warm-build scripts and every flutter/dart/xcodebuild process
# whose working directory is the wave3-next worktree.
WT=/Volumes/CrucialX9/flutter_app/.claude/worktrees/wave3-next
pkill -f "docker-ws/beta/wt_warm_ios_sim.sh|docker-ws/beta/r74_sims_ios_build.sh|sims.dart major --only build.ios" 2>/dev/null
for p in $(ps -axo pid=,command= | awk '/dartvm|flutter|xcodebuild/ && !/awk/ {print $1}'); do
  cwd=$(lsof -a -p "$p" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p')
  case "$cwd" in ("$WT"*) kill -TERM "$p" 2>/dev/null && echo "stopped $p";; esac
done | wc -l | sed 's/^/stopped processes: /'
sleep 3
# Build processes waiting on a lock can ignore SIGTERM: force what is left.
for p in $(ps -axo pid=,command= | awk '/dartvm|flutter|xcodebuild/ && !/awk/ {print $1}'); do
  cwd=$(lsof -a -p "$p" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p')
  case "$cwd" in ("$WT"*) kill -KILL "$p" 2>/dev/null;; esac
done
sleep 1
echo "worktree build processes left: $(for p in $(ps -axo pid=,command= | awk '/dartvm|flutter|xcodebuild/ && !/awk/ {print $1}'); do lsof -a -p $p -d cwd -Fn 2>/dev/null | grep -c wave3-next; done | paste -sd+ - | bc)"
echo "left: $(ps -axo command= | grep -c '[w]t_warm_ios_sim')"
