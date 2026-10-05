#!/bin/bash
# Create the UI-Update worktree beside the main checkout, on a new branch UI-Update from main,
# copy the ignored/untracked build inputs it needs, and run flutter pub get there.
set -uo pipefail
MAIN=/Volumes/CrucialX9/flutter_app
WT=/Volumes/CrucialX9/flutter_app-ui-update
SDK=$HOME/development/flutter-3.47.2
cd "$MAIN" || exit 1
if git show-ref --verify --quiet refs/heads/UI-Update; then echo "branch UI-Update already exists: $(git rev-parse --short UI-Update)"; exit 2; fi
[ -e "$WT" ] && { echo "$WT already exists"; exit 2; }
git worktree add -b UI-Update "$WT" main || { echo "FAIL worktree add"; exit 1; }
for f in .env android/key.properties android/local.properties android/app/google-services.json \
         android/app/libs/GoMknoon.aar tool/build/voice_call_release_defines.json ios/Runner/GoogleService-Info.plist; do
  if [ -f "$MAIN/$f" ] && ! git ls-files --error-unmatch "$f" >/dev/null 2>&1; then
    mkdir -p "$WT/$(dirname "$f")"; cp -p "$MAIN/$f" "$WT/$f" && echo "copied $f"
  fi
done
if [ -d "$MAIN/ios/Frameworks/GoMknoon.xcframework" ]; then
  mkdir -p "$WT/ios/Frameworks"; cp -Rp "$MAIN/ios/Frameworks/GoMknoon.xcframework" "$WT/ios/Frameworks/" && echo "copied ios/Frameworks/GoMknoon.xcframework"
fi
cd "$WT" || exit 1
"$SDK/bin/flutter" pub get 2>&1 | tail -2
echo "branch=$(git rev-parse --abbrev-ref HEAD) head=$(git log -1 --format='%h %s' | cut -c1-80) dirty=$(git status --porcelain | wc -l | tr -d ' ')"
git -C "$MAIN" worktree list
echo "R45 DONE"
