#!/bin/bash
# Read-only inventory of every git worktree except the main checkout. One block per worktree.
MAIN=/Volumes/CrucialX9/flutter_app
cd "$MAIN" || exit 1
echo "main=$(git rev-parse --short main) current=$(git rev-parse --abbrev-ref HEAD)@$(git rev-parse --short HEAD)"
git worktree list --porcelain | awk '/^worktree /{print substr($0,10)}' | while read -r WT; do
  [ "$WT" = "$MAIN" ] && continue
  echo "=== $WT"
  if [ ! -d "$WT" ]; then echo "MISSING (prunable)"; continue; fi
  head=$(git -C "$WT" rev-parse --short HEAD 2>/dev/null)
  br=$(git -C "$WT" symbolic-ref --short -q HEAD || echo detached)
  echo "head=$head branch=$br date=$(git -C "$WT" log -1 --format=%cd --date=short HEAD) subj=$(git -C "$WT" log -1 --format=%s HEAD | cut -c1-70)"
  if git merge-base --is-ancestor "$head" main; then echo "in_main=yes"; else
    echo "in_main=no ahead_of_main=$(git rev-list --count main.."$head") unique_vs_main=$(git cherry main "$head" | grep -c '^+')"
    git merge-base --is-ancestor "$head" HEAD && echo "in_current_branch=yes"
  fi
  st=$(git -C "$WT" status --porcelain --untracked-files=all 2>/dev/null)
  mod=$(printf '%s\n' "$st" | grep -c '^ \?[MADR]\|^[MADR]')
  unt=$(printf '%s\n' "$st" | grep -c '^??')
  same=0; diffr=0
  for f in $(printf '%s\n' "$st" | sed -n 's/^.. //p' | sed 's/.* -> //'); do
    [ -f "$WT/$f" ] || continue
    if cmp -s "$WT/$f" "$MAIN/$f"; then same=$((same+1)); else diffr=$((diffr+1)); fi
  done
  echo "dirty_tracked=$mod untracked=$unt same_as_main_checkout=$same different=$diffr"
  newest=$(printf '%s\n' "$st" | sed -n 's/^.. //p' | sed 's/.* -> //' | while read -r f; do [ -e "$WT/$f" ] && stat -f '%m %N' "$WT/$f"; done | sort -n | tail -1)
  [ -n "$newest" ] && echo "newest_dirty=$(date -r "${newest%% *}" '+%Y-%m-%d %H:%M') ${newest#* }" | sed "s|$WT/||"
  printf '%s\n' "$st" | sed -n 's/^.. //p' | sed 's|/.*||' | sort | uniq -c | sort -rn | head -6 | tr '\n' ';' | sed 's/^/top_dirs: /'; echo
  procs=$(ps -axo pid=,command= | grep -F "$WT" | grep -v -e grep -e r37_worktree | wc -l | tr -d ' ')
  echo "procs_mentioning=$procs du=$(du -sh "$WT" 2>/dev/null | cut -f1)"
done
echo "=== branches"
git for-each-ref --format='%(refname:short) %(objectname:short) %(committerdate:short)' refs/heads | while read -r b s d; do
  if git merge-base --is-ancestor "$b" main; then m=merged; else m="ahead=$(git rev-list --count main.."$b") unique=$(git cherry main "$b" | grep -c '^+')"; fi
  echo "$b $s $d $m"
done
echo "INVENTORY DONE"
