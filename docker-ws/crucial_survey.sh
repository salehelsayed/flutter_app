#!/bin/bash
# Read-only: CrucialX9 space survey (sizes in GB), DerivedData location, worktree list.
OUT="${1:-/tmp/crucial_survey.txt}"
{
df -g /Volumes/CrucialX9
echo "=== DerivedData real path ==="; ls -ld "$HOME/Library/Developer/Xcode/DerivedData"; (cd "$HOME/Library/Developer/Xcode/DerivedData" && pwd -P)
echo "=== top level ==="; du -sg /Volumes/CrucialX9/* 2>/dev/null | sort -rn | head -25
echo "=== flutter_app/build ==="; du -sg /Volumes/CrucialX9/flutter_app/build/* 2>/dev/null | sort -rn | head -40
echo "=== mac-development ==="; du -sg /Volumes/CrucialX9/mac-development/* 2>/dev/null | sort -rn | head -20
echo "=== worktrees ==="; git -C /Volumes/CrucialX9/flutter_app worktree list
echo SURVEY_DONE
} > "$OUT" 2>&1
