#!/bin/bash
# Read-only: grep -n a regex in one file of the fix worktree. Usage: r34_grep_wt.sh <regex> <path>
grep -nE "$1" "/Volumes/CrucialX9/flutter_app-r2-fixes-20261001/$2" | cut -c1-200 | head -40
