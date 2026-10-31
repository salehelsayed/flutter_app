#!/bin/bash
# Translate gate step 5: fetch, refuse unless origin/main is still <expected base> and <target> descends from it,
# then fast-forward origin main to <target> (plain push, no force; the remote rejects any non-fast-forward).
# Does not move the local main branch (it is checked out, dirty, in the live checkout).
#   host-run bash docker-ws/translate_main_push.sh <expected base sha> <target sha>
set -uo pipefail
BASE=${1:?base}; TGT=${2:?target}
cd /Volumes/CrucialX9/flutter_app || exit 2
git fetch origin main 2>&1 | tail -2; echo "fetch exit=${PIPESTATUS[0]}"
OM=$(git rev-parse origin/main); B=$(git rev-parse "$BASE^{commit}"); T=$(git rev-parse "$TGT^{commit}")
echo "origin/main=$OM expected=$B target=$T"
[ "$OM" = "$B" ] || { echo "STOP origin/main moved"; exit 3; }
git merge-base --is-ancestor "$B" "$T" || { echo "STOP target does not descend from base"; exit 4; }
echo "commits=$(git rev-list --count "$B..$T")"
git push origin "$T:refs/heads/main" 2>&1; rc=$?; echo "push exit=$rc"
git fetch origin main >/dev/null 2>&1; echo "origin/main now=$(git rev-parse origin/main)"; git ls-remote origin refs/heads/main
exit $rc
