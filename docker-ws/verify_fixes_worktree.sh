#!/bin/bash
# Check that git works inside the claude-docker image when the fixes worktree
# is mounted the way the patched launcher mounts it.
set -uo pipefail
WT=/Volumes/CrucialX9/flutter_app-fixes
GITDIR=/Volumes/CrucialX9/flutter_app/.git
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp \
  -v "$WT:/workspace" -v "$GITDIR:$GITDIR" -v "$WT:$WT" -w /workspace \
  claude-code-local bash -c '
    echo "--- toplevel: $(git rev-parse --show-toplevel)"
    echo "--- branch: $(git branch --show-current)"
    echo "--- status:"; git status --short | head
    echo "--- worktree list:"; git worktree list
    echo "--- CLAUDE.md: $(test -f CLAUDE.md && echo present)"
    echo "--- hooks: $(ls .claude/hooks | wc -l) files"
    echo "--- arch graph: $(test -f graphify-arch/graphify-out/graph.json && echo present)"
    echo "--- aar: $(test -f android/app/libs/GoMknoon.aar && echo present)"
    echo "--- env: $(test -f .env && echo present)"'
echo "--- launcher lines:"
awk '/GIT_COMMON_DIR|host-bridge-/ {print NR": "$0}' "$WT/scripts/run_claude_docker.sh"
echo VERIFY DONE
