#!/bin/bash
# Read-only: sizes of our test-output folders, leftover worktrees/copies, and symlinks from tool homes into them.
#   host-run bash docker-ws/host_test_output_sizes.sh <out file under .codex-test-logs/>
REPO="$(cd "$(dirname "$0")/.." && pwd)"; OUT="$REPO/${1:?out}"; mkdir -p "$(dirname "$OUT")"
{
echo "time $(date -u +%FT%TZ)"
echo "--- repo output folders (KB path)"
for d in .codex-test-logs .full_regression_logs build artifacts docker-ws/deploy-captures docker-ws/beta logs test-results; do
  [ -e "$REPO/$d" ] && du -sk "$REPO/$d" 2>/dev/null
done
echo "--- .codex-test-logs children older than 7 days (KB path)"
find "$REPO/.codex-test-logs" -mindepth 1 -maxdepth 1 -mtime +7 -exec du -sk {} + 2>/dev/null | sort -rn | head -40
echo "--- .codex-test-logs count / older-than-7d count"
find "$REPO/.codex-test-logs" -mindepth 1 -maxdepth 1 | wc -l; find "$REPO/.codex-test-logs" -mindepth 1 -maxdepth 1 -mtime +7 | wc -l
echo "--- .full_regression_logs children (KB path, top 20)"
find "$REPO/.full_regression_logs" -mindepth 1 -maxdepth 1 -exec du -sk {} + 2>/dev/null | sort -rn | head -20
echo "--- external drive top level (KB path)"
for d in /Volumes/CrucialX9/*; do case "$d" in */mac-development|*/DockerDesktop|*/AndroidAVDs) echo "skip $d (tool storage)";; *) du -sk "$d" 2>/dev/null;; esac; done
echo "--- git worktrees"
git -C "$REPO" worktree list
echo "--- symlinks from tool homes into the external drive (link -> target)"
for h in "$HOME/development" "$HOME/.gradle" "$HOME/Library/Developer" "$HOME/Library/Android" "$HOME/.cache" "$HOME/go" "$HOME/Library/Caches" "$HOME/.android" "$HOME/.pub-cache"; do
  [ -e "$h" ] && find "$h" -maxdepth 6 -type l 2>/dev/null | while read -r l; do t=$(readlink "$l"); case "$t" in /Volumes/CrucialX9/*) echo "$l -> $t";; esac; done
done
echo "--- DONE"
} > "$OUT" 2>&1
echo "wrote $OUT"
