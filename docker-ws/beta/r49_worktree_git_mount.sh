#!/bin/bash
# Apply r49_worktree_git_mount.py to the UI-Update worktree's launcher and check it.
cd /Volumes/CrucialX9/flutter_app || exit 1
python3 docker-ws/beta/r49_worktree_git_mount.py || exit 1
W=/Volumes/CrucialX9/flutter_app-ui-update
bash -n "$W/scripts/run_claude_docker.sh" && echo "syntax ok"
echo "common dir: $(git -C "$W" rev-parse --path-format=absolute --git-common-dir)"
git -C "$W" diff --stat
git -C "$W" diff | head -30
