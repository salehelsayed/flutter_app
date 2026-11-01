#!/bin/bash
# Read-only: state of a Codex-UI worktree for an iOS RunnerTests run (head, dirty count, Pods, Go xcframework), plus available
# iOS simulators (name, id, state). Prints no secrets and never reads GoogleService-Info.plist contents.
#   host-run bash docker-ws/codexui_wt_inspect.sh <worktree path>
W=${1:?worktree}; cd "$W" || exit 2
echo "head=$(git rev-parse --short HEAD) branch=$(git rev-parse --abbrev-ref HEAD) dirty=$(git status --porcelain --untracked-files=no | wc -l | tr -d ' ')"
git log --oneline -3
echo "pods_dir=$([ -d ios/Pods ] && echo yes || echo no) podfile_lock=$([ -f ios/Podfile.lock ] && echo yes || echo no) manifest_lock_match=$(cmp -s ios/Podfile.lock ios/Pods/Manifest.lock && echo yes || echo no)"
echo "go_xcframework=$(ls -d ios/Frameworks/*.xcframework ios/*.xcframework 2>/dev/null | head -3 | tr '\n' ' ')"
echo "googleservice_plist_present=$([ -f ios/Runner/GoogleService-Info.plist ] && echo yes || echo no)"
echo "flutter_generated=$([ -f ios/Flutter/Generated.xcconfig ] && echo yes || echo no)"
grep -n "IosNotificationRecoveryTests" -r ios/RunnerTests --include=*.swift -l 2>/dev/null | head -3
xcrun simctl list devices available | grep -E "iPhone" | head -12
