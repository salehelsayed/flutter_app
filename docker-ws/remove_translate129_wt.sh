#!/bin/bash
# Remove build/wt-translate-129 so its setup can start fresh (my own worktree, no work in it yet).
cd /Volumes/CrucialX9/flutter_app || exit 2
for w in build/wt-translate-129; do
  [ -d "$w" ] || { echo "absent $w"; continue; }
  echo "$w head=$(git -C "$w" rev-parse --short HEAD) tracked_changes=$(git -C "$w" status --porcelain --untracked-files=no | wc -l | tr -d ' ')"
  git worktree remove --force "$w" && echo "removed $w"
done
git worktree prune; df -h /Volumes/CrucialX9 | tail -1
