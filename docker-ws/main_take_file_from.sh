#!/bin/bash
# Take exact files from <commit> into local main and commit them, crediting the source commit.
#   host-run bash docker-ws/main_take_file_from.sh <expected main sha> <commit> "<subject>" <path>...
set -uo pipefail
EXP=${1:?expected main}; C=${2:?commit}; S=${3:?subject}; shift 3
cd /Volumes/CrucialX9/flutter_app || exit 2
[ "$(git rev-parse --abbrev-ref HEAD)" = main ] || { echo "STOP not on main"; exit 3; }
[ "$(git rev-parse HEAD)" = "$(git rev-parse "$EXP")" ] || { echo "STOP local main moved: $(git rev-parse --short HEAD)"; exit 4; }
git diff --cached --quiet || { echo "STOP something is staged"; exit 5; }
git checkout "$C" -- "$@" || exit 6
git commit -q -m "$S" -m "Taken from $(git rev-parse --short "$C") ($(git log -1 --format=%s "$C")): only the listed files." -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" && echo "commit $(git rev-parse --short HEAD)"
git show --stat --format= HEAD | tail -3
