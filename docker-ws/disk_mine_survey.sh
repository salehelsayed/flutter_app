#!/bin/bash
# Read-only: sizes (MB) of my candidate leftovers on CrucialX9.
M=/Volumes/CrucialX9/flutter_app; df -k /Volumes/CrucialX9 | tail -1
du -sm $M/build/wt-final128i/build $M/build/wt-release-128/build $M/build/wt-release-128 $M/build/wt-final128* $M/build/wt-release-1* 2>/dev/null
du -sm $M/.codex-test-logs/xver-127-128/*.apk 2>/dev/null
du -sm $M/.codex-test-logs/* 2>/dev/null | sort -rn | head -25
ls -ld $M/build/wt-* 2>/dev/null | awk '{print $NF}'
