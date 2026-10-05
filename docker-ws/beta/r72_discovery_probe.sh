#!/bin/bash
# Time the device-discovery commands SIMS uses, each bounded.
export PATH="$HOME/development/flutter-3.47.2/bin:/opt/homebrew/bin:$PATH"
cd /Volumes/CrucialX9/flutter_app/.claude/worktrees/wave3-next
for c in "flutter devices --machine" "flutter emulators --machine" "adb devices" "xcrun simctl list devices available --json" "xcrun devicectl list devices"; do
  s=$(date +%s); timeout 120 $c >/tmp/r72.out 2>&1; rc=$?; echo "$(( $(date +%s)-s ))s rc=$rc :: $c :: $(head -c 120 /tmp/r72.out | tr '\n' ' ')"
done
