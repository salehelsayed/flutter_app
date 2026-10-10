#!/bin/bash
# User-approved 2026-10-07: fast-forward main and wave3-baseline-20260930 to PR 7
# (fix/ios-direct-reaction-notification-tap), push both, then remove the two
# PR 7 build worktrees.
set -eu
cd /Volumes/CrucialX9/flutter_app
SRC=refs/remotes/origin/fix/ios-direct-reaction-notification-tap
git fetch -q origin fix/ios-direct-reaction-notification-tap
git rev-parse --short "$SRC"
git merge --ff-only "$SRC"
git fetch . "$SRC:refs/heads/main"
git push origin main wave3-baseline-20260930 2>&1 | tail -3
git ls-remote origin refs/heads/main refs/heads/wave3-baseline-20260930

bash docker-ws/beta/wave5/links_into.sh /Volumes/CrucialX9/flutter_app-pr7-fix /Volumes/CrucialX9/flutter_app-pr7-main
for wt in /Volumes/CrucialX9/flutter_app-pr7-fix /Volumes/CrucialX9/flutter_app-pr7-main; do
  git worktree remove --force "$wt" && echo "removed $wt"
done
git worktree prune
echo "free: $(df -h /Volumes/CrucialX9 | awk 'NR==2 {print $4" ("$5" used)"}')"
