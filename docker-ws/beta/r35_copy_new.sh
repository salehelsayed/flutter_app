#!/bin/bash
# Copy the fix worktree's two new files into the main checkout, then compare every changed file.
W=/Volumes/CrucialX9/flutter_app-r2-fixes-20261001; L=/Volumes/CrucialX9/flutter_app
cp "$W/lib/core/media/m4a_duration.dart" "$L/lib/core/media/m4a_duration.dart"
cp "$W/test/core/media/m4a_duration_test.dart" "$L/test/core/media/m4a_duration_test.dart"
cd "$W"; same=0; diff=0
for f in $(git status --porcelain | cut -c4-); do if cmp -s "$W/$f" "$L/$f"; then same=$((same+1)); else diff=$((diff+1)); echo "differs: $f"; fi; done
echo "identical $same, different $diff"
