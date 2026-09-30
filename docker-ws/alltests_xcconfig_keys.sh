#!/bin/bash
# Read-only: key names (values masked, except FLUTTER_BUILD_MODE/FLUTTER_TARGET) of the worktree Generated.xcconfig.
f=/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree/ios/Flutter/Generated.xcconfig
ls -la "$f"; sed -E '/^(FLUTTER_BUILD_MODE|FLUTTER_TARGET)=/!s/=.*/=<masked>/' "$f"
