#!/bin/bash
# PR 7 simulator check: build a signed debug simulator app (same args as SIMS
# profile ios.simulator.app) for one commit in its own worktree. Self-detaches.
# Usage: pr7_sim_build.sh <label> <commit>
set -u
LABEL=$1; COMMIT=$2
OUT=/Volumes/CrucialX9/flutter_app/docker-ws/beta/wave5/pr7_build_$LABEL.log
if [ -z "${PR7_BUILD_DETACHED:-}" ]; then
  PR7_BUILD_DETACHED=1 nohup bash "$0" "$@" >"$OUT" 2>&1 &
  echo "detached pid $! log $OUT"; exit 0
fi
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
SDK=$HOME/development/flutter-3.47.2/bin/flutter
WT=/Volumes/CrucialX9/flutter_app-pr7-$LABEL
cd /Volumes/CrucialX9/flutter_app || exit 1
git fetch -q origin fix/ios-direct-reaction-notification-tap
[ -d "$WT" ] || git worktree add --detach "$WT" "$COMMIT"
cd "$WT" && git checkout -q --detach "$COMMIT" && echo "HEAD $(git rev-parse --short HEAD)"
# untracked build inputs the checkout needs
for f in .env ios/Runner/GoMknoon.xcframework ios/Runner/GoMknoonNSE.xcframework ios/Runner/GoMknoon.inputs.sha256 ios/Runner/GoogleService-Info.plist; do
  [ -e "$f" ] || { [ -e "/Volumes/CrucialX9/flutter_app/$f" ] && cp -R "/Volumes/CrucialX9/flutter_app/$f" "$(dirname "$f")/" && echo "copied $f"; }
done
bash scripts/ensure_go_ios_bindings.sh 2>&1 | tail -3
date; "$SDK" pub get >/dev/null && echo "pub get ok"
(cd ios && pod install >/dev/null 2>&1 && echo "pod install ok" || echo "pod install FAILED")
FLUTTER_XCODE_CLANG_ENABLE_EXPLICIT_MODULES=NO "$SDK" build ios --simulator --debug --target=lib/main.dart \
  --dart-define=E2E_TEST_MODE=true --dart-define=SIMS_BUILD_PROFILE_ID=ios.simulator.app --dart-define=PRODUCTION_FCM=true
echo "build exit=$?"; date
ls -d build/ios/iphonesimulator/*.app 2>/dev/null
