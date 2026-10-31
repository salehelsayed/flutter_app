#!/bin/bash
# Read-only: for each worktree name under build/, list git status (tracked + untracked, top level) and processes with cwd or open files inside.
for w in "$@"; do
  p="/Volumes/CrucialX9/flutter_app/build/$w"
  echo "== $w"
  git -C "$p" status --short 2>&1 | head -10
  lsof -n -a -d cwd 2>/dev/null | awk -v p="$p" 'index($NF,p)==1 {print "CWD", $1, $2}'
done
