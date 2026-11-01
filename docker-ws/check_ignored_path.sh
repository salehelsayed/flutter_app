#!/bin/bash
# Read-only: in <worktree>, report whether <path> is git-ignored and untracked (never reads the file).
#   host-run bash docker-ws/check_ignored_path.sh <worktree> <path>
cd "${1:?worktree}" || exit 2; P=${2:?path}
git check-ignore -q -- "$P" && echo "ignored=yes" || echo "ignored=NO"
git ls-files --error-unmatch -- "$P" >/dev/null 2>&1 && echo "tracked=YES" || echo "tracked=no"
git status --porcelain -- "$P" | head -2
