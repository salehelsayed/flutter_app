#!/bin/bash
# Owner order 10-31 ("commit to have a clean worktree"): in the main checkout, fast-forward local main to origin/main,
# then commit ONLY flutter_app's own harness files under docker-ws/ (tracked edits + untracked helpers) as one
# test-only commit. Leaves every other change in place (not ours or unclear). Never stashes, never discards.
#   host-run bash docker-ws/main_cleanup_commit.sh <expected origin/main sha>
set -uo pipefail
EXP=${1:?expected origin/main}
M=/Volumes/CrucialX9/flutter_app; cd "$M" || exit 2
[ "$(git rev-parse --abbrev-ref HEAD)" = main ] || { echo "STOP not on main"; exit 3; }
git fetch origin main 2>&1 | tail -1
OM=$(git rev-parse origin/main); [ "$OM" = "$(git rev-parse "$EXP")" ] || { echo "STOP origin/main moved: $OM"; exit 4; }
git merge-base --is-ancestor HEAD "$OM" || { echo "STOP local main is not an ancestor of origin/main"; exit 5; }
echo "before head=$(git rev-parse --short HEAD)"
git merge --ff-only "$OM" 2>&1 | tail -2; echo "ff exit=${PIPESTATUS[0]} head=$(git rev-parse --short HEAD)"
[ "$(git rev-parse HEAD)" = "$OM" ] || { echo "STOP fast-forward did not land"; exit 6; }
git reset -q
git add -A -- docker-ws
git diff --cached --name-only | grep -v '^docker-ws/' && { echo "STOP staged files outside docker-ws"; git reset -q; exit 7; }
echo "staged=$(git diff --cached --name-only | wc -l | tr -d ' ')"
git commit -q -F - <<'MSG'
test(harness): flutter_app device and gate helper scripts

Commit the docker-ws helper scripts and harness edits that flutter_app used for the
128/129 device gates, store builds, relay checks, journey tests and phone pairing,
so the main checkout is clean. Test and harness files only; no app code.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
MSG
echo "commit exit=$? head=$(git rev-parse --short HEAD) parent=$(git rev-parse --short HEAD~1)"
echo "== remaining status"; git status --porcelain=v1 --untracked-files=normal
