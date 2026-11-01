#!/bin/bash
# Read-only: head, branch and tracked-dirty count of a git worktree, plus whether ios/Pods and the Go xcframeworks exist.
#   host-run bash docker-ws/wt_head_status.sh <worktree path>
W=${1:?worktree}
[ -d "$W" ] || { echo "no such dir"; exit 2; }
cd "$W" || exit 2
echo "head=$(git rev-parse --short HEAD 2>&1) branch=$(git rev-parse --abbrev-ref HEAD 2>&1)"
echo "tracked_dirty=$(git status --porcelain --untracked-files=no 2>/dev/null | wc -l | tr -d ' ')"
echo "pods=$([ -d ios/Pods ] && echo yes || echo no) xcframeworks=$(ls -d ios/Runner/*.xcframework 2>/dev/null | wc -l | tr -d ' ')"
