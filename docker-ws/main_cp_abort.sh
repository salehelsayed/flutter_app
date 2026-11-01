#!/bin/bash
# Abort an in-progress cherry-pick in the main checkout (only if one is in progress) and show the head.
#   host-run bash docker-ws/main_cp_abort.sh
cd /Volumes/CrucialX9/flutter_app || exit 2
[ -f .git/CHERRY_PICK_HEAD ] || { echo "no cherry-pick in progress"; git log --oneline -1; exit 0; }
git update-index -q --refresh >/dev/null; git cherry-pick --abort && echo "aborted"; git log --oneline -1
git status --porcelain --untracked-files=no | head -5
