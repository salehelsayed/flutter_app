#!/bin/bash
# Commit named test-only files in the Codex-UI audio worktree.  host-run bash docker-ws/cui_wt_commit.sh <msgfile> <file>...
set -euo pipefail
WT="${CUI_WT:-/Volumes/CrucialX9/flutter_app/build/wt-cui-audio}"
MSG="$1"; shift
cd "$WT"
for f in "$@"; do case "$f" in lib/*|android/app/src/main/*|ios/Runner/*|go-mknoon/*) echo "refused app path $f"; exit 3;; esac; done
git add -- "$@"
git diff --cached --name-only | sort | diff - <(printf '%s\n' "$@" | sort) >/dev/null || { echo "staged set differs"; git diff --cached --name-only; exit 3; }
git commit -q -F "$MSG"
git log -1 --format='%H %s'
