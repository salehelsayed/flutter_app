#!/bin/bash
# Inspect (default) or remove (arg "remove") the R2 fixer worktree and the r2val build copy.
WT=/Volumes/CrucialX9/flutter_app-r2-fixes-20261001
CP=/Volumes/CrucialX9/flutter_app-r2val
MAIN=/Volumes/CrucialX9/flutter_app
cd "$MAIN" || exit 1
echo "=== worktree list"; git worktree list
echo "=== r2val .git"; if [ -e "$CP/.git" ]; then ls -ld "$CP/.git"; else echo "no .git"; fi
echo "=== fixer files differing from main"
n=0
for f in $(git -C "$WT" diff --name-only HEAD; git -C "$WT" ls-files --others --exclude-standard); do
  case "$f" in .codex-test-logs/*) continue;; esac
  if ! cmp -s "$WT/$f" "$MAIN/$f"; then echo "DIFF $f"; n=$((n+1)); fi
done
echo "differing=$n"
echo "=== files changed in the worktree in the last 60 min"
find "$WT" \( -path "$WT/build" -o -path "$WT/.dart_tool" \) -prune -o -type f -mmin -60 -print 2>/dev/null | head -5
echo "=== worktree diff vs the merged patch"
if git -C "$WT" diff --binary HEAD | cmp -s - "$MAIN/docker-ws/beta/edits/r2fix.patch"; then echo "PATCH SAME"; else echo "PATCH CHANGED"; [ "$1" = remove ] && exit 2; fi
if [ "$1" = remove ]; then
  git worktree remove --force "$WT" && echo "REMOVED $WT"
  rm -rf "$CP" && echo "REMOVED $CP"
  git worktree prune; git worktree list
fi
