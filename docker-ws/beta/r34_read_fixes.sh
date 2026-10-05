#!/bin/bash
# Read-only: the R2 open-issues fix worktree: git state, changed files, and the fix status report.
W=/Volumes/CrucialX9/flutter_app-r2-fixes-20261001
cd "$W" || exit 1
echo "== branch: $(git rev-parse --abbrev-ref HEAD) head: $(git rev-parse --short HEAD)"
echo "== changed files:"; git status --porcelain | head -80
echo "== fix status report:"; cat artifacts/beta-20260927/R2-OPEN_REMAINING_ISSUES_FIX_STATUS.md
