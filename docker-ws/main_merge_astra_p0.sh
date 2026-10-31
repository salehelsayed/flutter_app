#!/bin/bash
# Owner order 10-31: merge Astra's reviewed P0 test branch commit into local main (main checkout). Test/docs-only
# branch. Keeps the not-ours uncommitted edits in place (git merge refuses if they would be touched).
#   host-run bash docker-ws/main_merge_astra_p0.sh <astra sha> <expected local main sha>
set -uo pipefail
A=${1:?astra sha}; EXP=${2:?expected main}
M=/Volumes/CrucialX9/flutter_app; cd "$M" || exit 2
[ "$(git rev-parse --abbrev-ref HEAD)" = main ] || { echo "STOP not on main"; exit 3; }
[ "$(git rev-parse HEAD)" = "$(git rev-parse "$EXP")" ] || { echo "STOP local main moved: $(git rev-parse --short HEAD)"; exit 4; }
git diff --cached --quiet || { echo "STOP something is staged"; exit 5; }
OUT=$(git diff --name-only "$(git merge-base HEAD "$A")" "$A" | grep -vE '^(test|integration_test|docs)/')
[ -z "$OUT" ] || { echo "STOP branch touches non-test files:"; echo "$OUT"; exit 6; }
git merge --no-ff "$A" -m "merge: Astra's P0 host journeys and native evidence boundaries" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" 2>&1 | tail -3
echo "merge exit=${PIPESTATUS[0]} head=$(git rev-parse HEAD) parents=$(git log -1 --format=%p)"
git status --porcelain=v1 --untracked-files=no
