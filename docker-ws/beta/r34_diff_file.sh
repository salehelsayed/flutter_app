#!/bin/bash
# Read-only: git diff of one file in the fix worktree. Usage: r34_diff_file.sh <path>
git -C /Volumes/CrucialX9/flutter_app-r2-fixes-20261001 diff -- "$1"
