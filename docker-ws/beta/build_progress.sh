#!/bin/bash
# Read-only: is the fixed build still working? (Mac-side view)
OUT=/Volumes/CrucialX9/flutter_app/artifacts/beta-20260925/build
echo "now: $(date '+%H:%M:%S')"
ps -axo pid,etime,%cpu,command | grep -E "build_beta_fixed|flutter_tools.*build ios|xcodebuild|swift-frontend|clang|ld |pod install" | grep -v grep | cut -c1-150 | head -12
echo "--- files"; ls -la -T "$OUT" | awk '{print $6,$7,$8,$9,$10}' | tail -8
echo "--- ios_rel log tail"; tail -5 "$OUT/ios_rel_build.log"
