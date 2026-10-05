#!/bin/bash
# For each worktree: dirty files whose content is in neither the main checkout nor any committed version of
# that path on any branch. Those are the only files whose work would be lost by removing the worktree.
MAIN=/Volumes/CrucialX9/flutter_app
cd "$MAIN" || exit 1
git worktree list --porcelain | awk '/^worktree /{print substr($0,10)}' | while read -r WT; do
  [ "$WT" = "$MAIN" ] && continue
  [ -d "$WT" ] || continue
  uniq=0; old=0; list=""
  for f in $(git -C "$WT" status --porcelain --untracked-files=all 2>/dev/null | sed -n 's/^.. //p' | sed 's/.* -> //'); do
    [ -f "$WT/$f" ] || continue
    cmp -s "$WT/$f" "$MAIN/$f" && continue
    h=$(git hash-object "$WT/$f")
    if git log --all --no-abbrev --raw --format= -- "$f" 2>/dev/null | awk '{print $4}' | grep -qx "$h"; then
      old=$((old+1))
    else
      uniq=$((uniq+1))
      if [ -e "$MAIN/$f" ]; then tag=mod; else tag=new; fi
      list="$list
    $tag $(wc -l < "$WT/$f" | tr -d ' ')L $f"
    fi
  done
  echo "=== $WT committed_elsewhere=$old unique=$uniq"
  printf '%s\n' "$list" | sed '/^$/d' | head -40
done
echo "UNIQUE DONE"
