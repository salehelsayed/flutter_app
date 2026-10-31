#!/bin/bash
# Start cherry-pick of <sha> on local main, print conflict hunks of conflicted files, leave the cherry-pick in progress.
#   host-run bash docker-ws/main_cp_show_conflict.sh <expected main> <sha>
cd /Volumes/CrucialX9/flutter_app || exit 2
[ "$(git rev-parse HEAD)" = "$(git rev-parse "$1")" ] || { echo "STOP moved"; exit 4; }
git cherry-pick -x "$2" > /dev/null 2>&1
for f in $(git diff --name-only --diff-filter=U); do echo "=== $f"; awk '/^<<<<<<<|^=======|^>>>>>>>/{print NR": "$0}' "$f"; done
