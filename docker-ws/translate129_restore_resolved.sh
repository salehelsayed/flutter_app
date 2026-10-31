#!/bin/bash
# Translation 129 gate: restore Package.resolved in build/wt-translate-129 after a device build re-resolved it, then show tracked state.
cd /Volumes/CrucialX9/flutter_app/build/wt-translate-129 || exit 2
git diff --stat -- ios/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved | tail -1
git checkout -- ios/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved
echo "head=$(git rev-parse --short HEAD) tracked_dirty=$(git status --porcelain --untracked-files=no | wc -l | tr -d " ")"
