#!/bin/bash
# Builds the merge of the working branch into main with main as first parent,
# without switching branches, then fast-forwards the working branch onto it.
set -eu
cd /Volumes/CrucialX9/flutter_app
git fetch -q origin
MAIN=$(git rev-parse origin/main)
BR=$(git rev-parse wave3-baseline-20260930)
TREE=$(git merge-tree --write-tree origin/main wave3-baseline-20260930)
MSG="Merge branch 'wave3-baseline-20260930' into main

Brings in call preflight diagnostics, relay v1.11.1, call runtime and iOS
audio session fixes, the Orbit settings button, and beta harness scripts.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
M=$(git commit-tree "$TREE" -p "$MAIN" -p "$BR" -m "$MSG")
git merge -q --ff-only "$M"
git log --oneline -1
echo "MAIN_PARENT=$MAIN"
