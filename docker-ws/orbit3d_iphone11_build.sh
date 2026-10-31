#!/bin/bash
# Owner preview (10-30): 3D Orbit active-center commit merged onto current main in build/wt-translate-129 (local merge,
# never pushed), then an iPhone device build with TRANSLATE_PREVIEW=true on the Hetzner test relay.
#   host-run docker-ws/with_native_lease.py <log> -- bash docker-ws/orbit3d_iphone11_build.sh <main sha> <branch sha> <evidence dir> <build-number>
set -uo pipefail
MAIN=${1:?main}; BR=${2:?branch}; EV=${3:?evidence}; BN=${4:?bn}
REPO=/Volumes/CrucialX9/flutter_app; W=$REPO/build/wt-translate-129; E="$REPO/$EV"; mkdir -p "$E"
export PATH="$HOME/development/flutter-3.47.2/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
cd "$W" || exit 2
git checkout -- ios/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved 2>/dev/null
[ -z "$(git status --porcelain --untracked-files=no)" ] || { git status --porcelain --untracked-files=no; echo "STOP tree dirty"; exit 3; }
git checkout --detach "$MAIN" 2>&1 | tail -1
git merge --no-ff "$BR" -m "local preview: merge 3D Orbit active center onto main (not pushed)" > "$E/merge.log" 2>&1; rc=$?
cat "$E/merge.log" | tail -3
[ $rc -eq 0 ] || { git merge --abort; echo "MERGE CONFLICT (aborted)"; exit 9; }
echo "head=$(git rev-parse HEAD) parents=$(git log -1 --format=%P HEAD)"
bash "$REPO/docker-ws/wt_checks.sh" wt-translate-129 > "$E/wt_checks.log" 2>&1; echo "wt_checks exit=$?"; grep -E "errors=|warnings=" "$E/wt_checks.log"
DD_OVERRIDE="$HOME/tmp-dd-161" bash "$REPO/docker-ws/ios_device_build_internal.sh" wt-translate-129 "$EV/ios" "$BN" "--dart-define=TRANSLATE_PREVIEW=true" > "$E/ios_build.log" 2>&1
echo "ios_device exit=$?"; tail -2 "$E/ios_build.log"
git checkout -- ios/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved 2>/dev/null
echo "done $(date -u +%T) tracked_dirty=$(git status --porcelain --untracked-files=no | wc -l | tr -d ' ')"
