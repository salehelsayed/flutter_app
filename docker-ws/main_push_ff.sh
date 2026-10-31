#!/bin/bash
# Fetch, then fast-forward push local main to origin/main only if origin/main is still <expected origin sha>.
#   host-run bash docker-ws/main_push_ff.sh <expected origin sha> <expected local sha>
set -uo pipefail
EO=${1:?expected origin}; EL=${2:?expected local}
cd /Volumes/CrucialX9/flutter_app || exit 2
[ "$(git rev-parse --abbrev-ref HEAD)" = main ] || { echo "STOP not on main"; exit 3; }
[ "$(git rev-parse HEAD)" = "$(git rev-parse "$EL")" ] || { echo "STOP local main moved: $(git rev-parse --short HEAD)"; exit 4; }
git fetch -q origin main || { echo "STOP fetch failed"; exit 5; }
O=$(git rev-parse origin/main)
[ "$O" = "$(git rev-parse "$EO")" ] || { echo "STOP origin moved: $(git rev-parse --short "$O")"; exit 6; }
git merge-base --is-ancestor "$O" HEAD || { echo "STOP not a fast-forward"; exit 7; }
git push origin HEAD:main 2>&1 | tail -2
git fetch -q origin main; echo "origin/main=$(git rev-parse origin/main) local=$(git rev-parse HEAD)"
