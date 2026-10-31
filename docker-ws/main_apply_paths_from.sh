#!/bin/bash
# Apply only <path>... of <commit>'s own diff onto local main (git apply, stops on any mismatch) and commit,
# keeping the source subject and crediting the commit.
#   host-run bash docker-ws/main_apply_paths_from.sh <expected main sha> <commit> <path>...
set -uo pipefail
EXP=${1:?expected main}; C=${2:?commit}; shift 2
cd /Volumes/CrucialX9/flutter_app || exit 2
[ "$(git rev-parse --abbrev-ref HEAD)" = main ] || { echo "STOP not on main"; exit 3; }
[ "$(git rev-parse HEAD)" = "$(git rev-parse "$EXP")" ] || { echo "STOP local main moved: $(git rev-parse --short HEAD)"; exit 4; }
git diff --cached --quiet || { echo "STOP something is staged"; exit 5; }
git update-index -q --refresh >/dev/null; git show "$C" --format= -- "$@" | git apply --index || { echo "STOP apply failed"; exit 6; }
git commit -q -m "$(git log -1 --format=%s "$C")" -m "(cherry picked from commit $(git rev-parse "$C"), only: $*)" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" && echo "commit $(git rev-parse --short HEAD)"
git show --stat --format= HEAD | tail -3
