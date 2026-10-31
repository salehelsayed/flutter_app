#!/bin/bash
# Cherry-pick reviewed commits onto local main (main checkout) in order. Stops at the first conflict and aborts it.
#   host-run bash docker-ws/main_cherry_pick.sh <expected main sha> <sha>...
set -uo pipefail
EXP=${1:?expected main}; shift
cd /Volumes/CrucialX9/flutter_app || exit 2
[ "$(git rev-parse --abbrev-ref HEAD)" = main ] || { echo "STOP not on main"; exit 3; }
[ "$(git rev-parse HEAD)" = "$(git rev-parse "$EXP")" ] || { echo "STOP local main moved: $(git rev-parse --short HEAD)"; exit 4; }
git diff --cached --quiet || { echo "STOP something is staged"; exit 5; }
for c in "$@"; do
  echo "== $c $(git log -1 --format=%s "$c")"; git show --stat --format= "$c" | tail -6
  if ! git cherry-pick -x "$c" > /tmp/cp_out.txt 2>&1; then
    cat /tmp/cp_out.txt | tail -5; git diff --name-only --diff-filter=U; git cherry-pick --abort; echo "STOP conflict at $c"; exit 6
  fi
  echo "picked -> $(git rev-parse --short HEAD)"
done
git log --oneline -5
