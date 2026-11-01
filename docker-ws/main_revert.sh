#!/bin/bash
# Revert local commits on main (main checkout) in the given order with normal revert commits. Stops and aborts at the first
# conflict. Each revert message names the reason given.
#   host-run bash docker-ws/main_revert.sh <expected main sha> "<reason>" <sha>...
set -uo pipefail
EXP=${1:?expected main}; WHY=${2:?reason}; shift 2
cd /Volumes/CrucialX9/flutter_app || exit 2
[ "$(git rev-parse --abbrev-ref HEAD)" = main ] || { echo "STOP not on main"; exit 3; }
[ "$(git rev-parse HEAD)" = "$(git rev-parse "$EXP")" ] || { echo "STOP local main moved: $(git rev-parse --short HEAD)"; exit 4; }
git diff --cached --quiet || { echo "STOP something is staged"; exit 5; }
git update-index -q --refresh >/dev/null
for c in "$@"; do
  if ! git revert --no-edit --no-commit "$c" > /tmp/rv_out.txt 2>&1; then
    tail -4 /tmp/rv_out.txt; git diff --name-only --diff-filter=U; git revert --abort; echo "STOP conflict reverting $c"; exit 6
  fi
  git commit -q -m "Revert \"$(git log -1 --format=%s "$c")\"" -m "This reverts commit $(git rev-parse "$c"). $WHY" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
  echo "reverted $c -> $(git rev-parse --short HEAD)"
done
git log --oneline -3
