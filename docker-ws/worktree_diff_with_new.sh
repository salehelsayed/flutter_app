#!/bin/bash
# Diff of a worktree under build/ including new untracked files (intent-to-add), written to a file.
#   host-run bash docker-ws/worktree_diff_with_new.sh <worktree dir under build/> <out file under build/>
REPO="$(cd "$(dirname "$0")/.." && pwd)"; W="$REPO/${1:?wt}"
git -C "$W" add -N . && git -C "$W" diff --stat && git -C "$W" diff > "$REPO/${2:?out}" && shasum -a 256 "$REPO/$2"
