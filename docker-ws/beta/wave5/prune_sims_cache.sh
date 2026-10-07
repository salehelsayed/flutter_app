#!/bin/bash
# Keep only the newest input-digest entry per build profile in the SIMS build caches; delete older (unusable) entries.
#   prune_sims_cache.sh [--delete]     (default: dry run, prints what would go)
M=/Volumes/CrucialX9/flutter_app
total=0
for C in "$M/build/sims/cache" "$M/.claude/worktrees/wave3-next/build/sims/cache"; do
  for P in "$C"/*/; do
    old=$(ls -dt "$P"*/ 2>/dev/null | tail -n +2)
    for e in $old; do
      k=$(du -sk "$e" | cut -f1); total=$((total+k))
      if [ "$1" = "--delete" ]; then rm -rf "$e"; fi
    done
  done
done
echo "$( [ "$1" = "--delete" ] && echo deleted || echo would delete ) $((total/1024/1024)) GB of stale cache entries"
