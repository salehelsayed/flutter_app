#!/bin/bash
# Remove the flutter_app session's own build worktrees whose work is pushed (translation port, call fixes).
cd /Volumes/CrucialX9/flutter_app || exit 2
for w in build/wt-callfix-169 build/wt-translate-main; do
  [ -d "$w" ] || { echo "absent $w"; continue; }
  echo "$w head=$(git -C "$w" rev-parse --short HEAD) tracked_changes=$(git -C "$w" status --porcelain --untracked-files=no | wc -l | tr -d ' ')"
  git worktree remove --force "$w" && echo "removed $w"
done
git worktree prune; df -h /Volumes/CrucialX9 | tail -1
