#!/bin/bash
# Translation 129 gate: start the rebase in build/wt-translate-129 and print the conflicted TESTING.md hunks, then abort.
#   host-run bash docker-ws/translate129_rebase_show.sh <old base> <new base>
set -uo pipefail
cd /Volumes/CrucialX9/flutter_app/build/wt-translate-129 || exit 2
git rebase --rebase-merges --onto "${2:?new}" "${1:?old}" > /dev/null 2>&1
echo "stopped at: $(git log -1 --format='%h %s' REBASE_HEAD 2>/dev/null)"
git diff --name-only --diff-filter=U
awk '/^<<<<<<< /{on=1; n++} on{print NR": "$0} /^>>>>>>> /{on=0; print "-----"}' docs/testing/TESTING.md | cut -c1-200 | head -120
git rebase --abort; echo "aborted head=$(git rev-parse --short HEAD) dirty=$(git status --porcelain --untracked-files=no | wc -l | tr -d ' ')"
