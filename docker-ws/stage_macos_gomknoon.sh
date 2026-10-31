#!/bin/bash
# Copy the git-ignored macOS GoMknoon.xcframework from the main checkout into a worktree (no overwrite).
S=/Volumes/CrucialX9/flutter_app/macos/Runner/GoMknoon.xcframework; D="$1/macos/Runner/GoMknoon.xcframework"
[ -e "$D" ] && { echo "target exists"; exit 0; }
cp -a "$S" "$D" && echo copied
git -C "$1" check-ignore -q macos/Runner/GoMknoon.xcframework && echo "git-ignored in target"
