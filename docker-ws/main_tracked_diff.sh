#!/bin/bash
# Read-only: diff stat and short diffs of the modified tracked files in the main checkout (run on the Mac for speed).
#   host-run bash docker-ws/main_tracked_diff.sh <out-file-in-repo>
M=/Volumes/CrucialX9/flutter_app; OUT="$M/${1:?out}"
cd "$M" || exit 2
{
  git diff --stat
  for f in $(git diff --name-only); do
    echo "=================== $f"
    git log -1 --format='last commit: %h %ad %s' --date=short -- "$f"
    stat -f 'mtime: %Sm' -t '%Y-%m-%d %H:%M' "$f"
    git diff -- "$f" | head -60
  done
} > "$OUT" 2>&1
wc -l < "$OUT"
