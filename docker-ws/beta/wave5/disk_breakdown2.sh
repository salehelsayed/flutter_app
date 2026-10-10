#!/bin/bash
# Read-only: largest children (size, last change) of build/ and .codex-test-logs/ in the main checkout and the worktree.
M=/Volumes/CrucialX9/flutter_app; W=$M/.claude/worktrees/wave3-next
for d in "$M/build" "$M/build/sims" "$M/.codex-test-logs" "$W/build" "$W/build/sims"; do
  echo "== ${d#$M/}"
  du -sk "$d"/* "$d"/.[!.]* 2>/dev/null | sort -rn | head -8 | while read k p; do printf '%8.1f GB  %s  %s\n' "$(echo "$k/1048576" | bc -l)" "$(stat -f %Sm -t %m-%d "$p")" "${p#$M/}"; done
done
