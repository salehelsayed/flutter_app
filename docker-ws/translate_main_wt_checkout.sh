#!/bin/bash
# Detach build/wt-translate-main at <rev>; refuses if the tree has tracked changes.
#   host-run bash docker-ws/translate_main_wt_checkout.sh <rev>
cd /Volumes/CrucialX9/flutter_app/build/wt-translate-main || exit 2
[ -z "$(git status --porcelain --untracked-files=no)" ] || { echo "DIRTY"; git status --porcelain --untracked-files=no | head; exit 3; }
git checkout --detach "${1:?rev}" 2>&1 | tail -2; echo "head=$(git rev-parse --short HEAD) dirty=$(git status --porcelain --untracked-files=no | wc -l | tr -d ' ')"
