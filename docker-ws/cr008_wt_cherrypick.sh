#!/bin/bash
# CR-008 gate: create build/wt-cr008 detached at <base> and cherry-pick ONLY <commit> onto it (abort and exit 9 on conflict).
#   host-run bash docker-ws/cr008_wt_cherrypick.sh <base> <commit>
set -uo pipefail
BASE=${1:?base}; C=${2:?commit}
REPO=/Volumes/CrucialX9/flutter_app; W=$REPO/build/wt-cr008
cd "$REPO" || exit 2
[ -d "$W" ] && { echo "tree exists head=$(git -C "$W" rev-parse --short HEAD)"; exit 4; }
git worktree add --detach "$W" "$BASE" 2>&1 | tail -1
cd "$W" || exit 2
git cherry-pick -x "$C" 2>&1 | tail -3; rc=${PIPESTATUS[0]}
if [ "$rc" -ne 0 ]; then git diff --name-only --diff-filter=U; git cherry-pick --abort; echo "CHERRY-PICK CONFLICT (aborted)"; exit 9; fi
echo "head=$(git rev-parse HEAD) parent=$(git rev-parse HEAD~1)"
git show --stat --format='%h %an | %s' HEAD | tail -5
echo "tracked_dirty=$(git status --porcelain --untracked-files=no | wc -l | tr -d ' ')"
