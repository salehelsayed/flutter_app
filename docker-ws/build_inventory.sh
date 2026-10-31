#!/bin/bash
# Read-only: worktrees under the main checkout build/ with size, HEAD, dirty count, and whether HEAD is on origin.
cd /Volumes/CrucialX9/flutter_app || exit 2
git worktree list --porcelain | awk "/^worktree /{print \$2}" | grep "/flutter_app/build/" | while read w; do
  s=$(du -sg "$w" 2>/dev/null | cut -f1); h=$(git -C "$w" rev-parse --short HEAD 2>/dev/null); d=$(git -C "$w" status --porcelain 2>/dev/null | wc -l | tr -d " ")
  on=$(git branch -r --contains "$h" 2>/dev/null | grep -c origin/main); echo "${s}G $w head=$h dirty=$d on_origin_main=$on"; done
echo "== other build/ dirs (GB)"; du -sg build/* 2>/dev/null | sort -nr | head -12
df -g /Volumes/CrucialX9 | tail -1
