#!/bin/bash
# Background motion 129 gate: move build/wt-translate-129 to <target> when <target> descends from the current HEAD.
#   host-run bash docker-ws/translate129_wt_move.sh <target>
set -uo pipefail
TGT=${1:?target}
cd /Volumes/CrucialX9/flutter_app/build/wt-translate-129 || exit 2
OLD=$(git rev-parse HEAD)
git merge-base --is-ancestor "$OLD" "$TGT" || { echo "target does not descend from $OLD"; exit 3; }
echo "changed files $OLD..$TGT:"; git diff --name-only "$OLD" "$TGT"
git checkout --detach "$TGT" 2>&1 | tail -1
echo "head=$(git rev-parse HEAD) tracked_dirty=$(git status --porcelain --untracked-files=no | wc -l | tr -d ' ')"
