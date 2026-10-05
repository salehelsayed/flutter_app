#!/bin/bash
# Copy the git-ignored macOS Go xcframework from the main checkout into the wave3-next worktree.
M=/Volumes/CrucialX9/flutter_app; W=$M/.claude/worktrees/wave3-next
[ -d "$M/macos/Runner/GoMknoon.xcframework" ] || { echo "main has no macOS xcframework"; exit 1; }
rm -rf "$W/macos/Runner/GoMknoon.xcframework"; cp -Rp "$M/macos/Runner/GoMknoon.xcframework" "$W/macos/Runner/" && echo copied
