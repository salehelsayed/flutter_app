#!/bin/bash
# Write the uncommitted diff of a repo worktree under build/ to a file.  host-run bash docker-ws/worktree_diff.sh <worktree dir under build/> <out file under build/>
REPO="$(cd "$(dirname "$0")/.." && pwd)"
git -C "$REPO/${1:?wt}" diff --stat
git -C "$REPO/$1" diff > "$REPO/${2:?out}"
shasum -a 256 "$REPO/$2"
