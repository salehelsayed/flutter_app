#!/bin/bash
# Read-only: compare one repo-relative file between main checkout and worktree; print wt lines if asked.
m=/Volumes/CrucialX9/flutter_app/$1; w=/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree/$1
cmp "$m" "$w" && echo SAME || diff "$m" "$w" | head -40
[ -n "$2" ] && sed -n "$2,$3p" "$w"
