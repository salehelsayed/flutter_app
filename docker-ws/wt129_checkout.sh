#!/bin/bash
# Point build/wt-translate-129 at <sha> (detached) for a lane run. Restores the tracked Package.resolved files first.
# Ignored build outputs (the 129 store AAB/IPA) are untouched. Stops if tracked files are dirty.
#   host-run bash docker-ws/wt129_checkout.sh <sha>
set -uo pipefail
S=${1:?sha}; cd /Volumes/CrucialX9/flutter_app/build/wt-translate-129 || exit 2
git checkout -- ios/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved ios/Runner.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved 2>/dev/null
[ -z "$(git status --porcelain --untracked-files=no)" ] || { git status --porcelain --untracked-files=no; echo "STOP tree dirty"; exit 3; }
echo "from=$(git rev-parse --short HEAD)"; git checkout --detach "$S" 2>&1 | tail -1
echo "head=$(git rev-parse HEAD) tracked_dirty=$(git status --porcelain --untracked-files=no | wc -l | tr -d ' ')"
ls -la build/app/outputs/bundle/release/app-release.aab build/ios/ipa/mknoon.ipa 2>/dev/null | awk '{print "kept", $5, $NF}'
