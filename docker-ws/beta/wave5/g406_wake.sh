#!/bin/bash
# Plan 406: run the wake-token binary freshness check in the worktree and on main.
for d in /Volumes/CrucialX9/flutter_app/.claude/worktrees/go-upgrade-406 /Volumes/CrucialX9/flutter_app; do
  echo "######## $d"; cd "$d" && bash scripts/check_wake_token_binary_freshness.sh 2>&1 | tail -8
  ls -d macos/Runner/GoMknoon.xcframework 2>&1
done
