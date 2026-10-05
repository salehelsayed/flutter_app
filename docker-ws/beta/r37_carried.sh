#!/bin/bash
# For each worktree's unique dirty files (content not in the main checkout and never committed): how many of the
# lines the worktree ADDED (vs its own HEAD; whole file if untracked) are missing from the main checkout's file.
# Lines are trimmed; lines of 3 chars or fewer are ignored. missing=0 means the work was carried over.
MAIN=/Volumes/CrucialX9/flutter_app
T=$(mktemp -d)
cd "$MAIN" || exit 1
git worktree list --porcelain | awk '/^worktree /{print substr($0,10)}' | while read -r WT; do
  [ "$WT" = "$MAIN" ] && continue
  [ -d "$WT" ] || continue
  tot_add=0; tot_miss=0; rows=""
  for f in $(git -C "$WT" status --porcelain --untracked-files=all 2>/dev/null | sed -n 's/^.. //p' | sed 's/.* -> //'); do
    [ -f "$WT/$f" ] || continue
    cmp -s "$WT/$f" "$MAIN/$f" && continue
    h=$(git hash-object "$WT/$f")
    git log --all --no-abbrev --raw --format= -- "$f" 2>/dev/null | awk '{print $4}' | grep -qx "$h" && continue
    if git -C "$WT" ls-files --error-unmatch "$f" >/dev/null 2>&1; then
      git -C "$WT" diff --no-color -U0 HEAD -- "$f" | grep '^+' | grep -v '^+++' | sed 's/^+//' > "$T/a"
    else
      cat "$WT/$f" > "$T/a"
    fi
    sed 's/^[[:space:]]*//; s/[[:space:]]*$//' "$T/a" | awk 'length>3' | sort -u > "$T/as"
    if [ -f "$MAIN/$f" ]; then sed 's/^[[:space:]]*//; s/[[:space:]]*$//' "$MAIN/$f" | sort -u > "$T/ms"; else : > "$T/ms"; fi
    add=$(wc -l < "$T/as" | tr -d ' '); miss=$(comm -23 "$T/as" "$T/ms" | wc -l | tr -d ' ')
    tot_add=$((tot_add+add)); tot_miss=$((tot_miss+miss))
    [ "$miss" -gt 0 ] && rows="$rows
    missing=$miss/$add $f"
  done
  echo "=== $WT added_lines=$tot_add missing_from_main=$tot_miss"
  printf '%s\n' "$rows" | sed '/^$/d' | sort -t= -k2 -rn | head -25
done
rm -rf "$T"
echo "CARRIED DONE"
