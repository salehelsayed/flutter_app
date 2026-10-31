#!/bin/bash
# Read-only: for each build/wt-<name> worktree print dirty-file count, whether HEAD is in origin/main, and processes with cwd inside it.
#   host-run bash docker-ws/wt_cleanup_check.sh <name>...
R=/Volumes/CrucialX9/flutter_app
cwds=$(lsof -a -d cwd -Fn 2>/dev/null | sed -n 's/^n//p')
for n in "$@"; do
  W="$R/build/$n"
  [ -d "$W" ] || { echo "$n missing"; continue; }
  d=$(git -C "$W" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  h=$(git -C "$W" rev-parse --short HEAD)
  if git -C "$R" merge-base --is-ancestor "$h" origin/main 2>/dev/null; then a=in_main; else a=not_in_main; fi
  p=$(printf '%s\n' "$cwds" | grep -c "^$W\(/\|$\)")
  sz=$(du -sk "$W" 2>/dev/null | cut -f1)
  echo "$n head=$h dirty=$d $a procs=$p size_mb=$((sz/1024))"
done
