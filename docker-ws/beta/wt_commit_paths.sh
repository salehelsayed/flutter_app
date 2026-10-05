#!/bin/bash
# Commit only the given paths in the next-batch worktree, message in docker-ws/beta/wt_commit_msg.txt.
W=/Volumes/CrucialX9/flutter_app/.claude/worktrees/wave3-next
cd "$W" || exit 1
git add -- "$@" && git commit -q -F /Volumes/CrucialX9/flutter_app/docker-ws/beta/wt_commit_msg.txt -- "$@" && git log -1 --stat --format='%h %s' | tail -8
