#!/bin/bash
# Finish an in-progress cherry-pick on local main after a test-file conflict was resolved: add the named files, continue.
#   host-run bash docker-ws/main_cp_continue.sh <file>...
cd /Volumes/CrucialX9/flutter_app || exit 2
[ -f .git/CHERRY_PICK_HEAD ] || { echo "STOP no cherry-pick in progress"; exit 3; }
git add -- "$@"
[ -z "$(git diff --name-only --diff-filter=U)" ] || { echo "STOP still conflicted"; git diff --name-only --diff-filter=U; exit 4; }
GIT_EDITOR=true git cherry-pick --continue 2>&1 | tail -1; echo "head=$(git rev-parse --short HEAD)"
