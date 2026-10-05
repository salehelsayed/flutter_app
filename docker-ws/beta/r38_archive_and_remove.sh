#!/bin/bash
# Archive each worktree's uncommitted work (tracked diff + untracked files up to 5 MB), then remove the worktree.
# Afterwards delete the 9 local branches that are merged or contained elsewhere (their shas are recorded first).
MAIN=/Volumes/CrucialX9/flutter_app
ARC=$MAIN/artifacts/worktree-archive-20261001
mkdir -p "$ARC"
cd "$MAIN" || exit 1
git worktree list --porcelain | awk '/^worktree /{print substr($0,10)}' > "$ARC/worktrees-before.txt"
while read -r WT; do
  [ "$WT" = "$MAIN" ] && continue
  [ -d "$WT" ] || { echo "SKIP missing $WT"; continue; }
  name=$(printf '%s' "$WT" | sed 's|^/||; s|/|__|g')
  D="$ARC/$name"; mkdir -p "$D"
  {
    echo "path=$WT"
    echo "head=$(git -C "$WT" rev-parse HEAD)"
    echo "branch=$(git -C "$WT" symbolic-ref --short -q HEAD || echo detached)"
  } > "$D/info.txt"
  git -C "$WT" status --porcelain --untracked-files=all > "$D/status.txt"
  git -C "$WT" diff --binary HEAD > "$D/tracked.patch" || { echo "FAIL diff $WT"; continue; }
  : > "$D/untracked-list.txt"; : > "$D/untracked-skipped-over-5MB.txt"
  git -C "$WT" ls-files --others --exclude-standard | while read -r f; do
    sz=$(stat -f %z "$WT/$f" 2>/dev/null || echo 0)
    if [ "$sz" -le 5242880 ]; then echo "$f" >> "$D/untracked-list.txt"; else echo "$sz $f" >> "$D/untracked-skipped-over-5MB.txt"; fi
  done
  if [ -s "$D/untracked-list.txt" ]; then
    (cd "$WT" && tar czf "$D/untracked.tgz" -T "$D/untracked-list.txt") || { echo "FAIL tar $WT"; continue; }
    n_tar=$(tar tzf "$D/untracked.tgz" | wc -l | tr -d ' '); n_list=$(wc -l < "$D/untracked-list.txt" | tr -d ' ')
    [ "$n_tar" = "$n_list" ] || { echo "FAIL tar count $n_tar/$n_list $WT"; continue; }
  fi
  echo "ARCHIVED $WT patch=$(wc -c < "$D/tracked.patch" | tr -d ' ')B untracked=$(wc -l < "$D/untracked-list.txt" | tr -d ' ') skipped=$(wc -l < "$D/untracked-skipped-over-5MB.txt" | tr -d ' ')"
  if git worktree remove --force --force "$WT" 2>"$D/remove.err"; then
    echo "REMOVED $WT"
  else
    echo "git remove failed: $(head -1 "$D/remove.err")"; rm -rf "$WT"; git worktree prune
    [ -d "$WT" ] && echo "FAIL remove $WT" || echo "REMOVED(rm) $WT"
  fi
done < "$ARC/worktrees-before.txt"
git worktree prune
echo "=== branches"
B="codex/ci-regression-check codex/dual-stack-release-validation codex/preserve-shared-libp2p-connections codex/relay-deployment-receipt codex/turn-network-and-call-diagnostics feat/ipv6-happy-eyeballs fix/beta-call-labels-20260924 fix/diagnostics-apns-lifetime-20260920 fix/r2-open-issues-20261001"
for b in $B; do echo "$b $(git rev-parse "$b" 2>/dev/null)"; done > "$ARC/deleted-branches.txt"
for b in $B; do git branch -D "$b" 2>&1; done
echo "=== after"; git worktree list; git branch --list
du -sh "$ARC"
echo "R38 DONE"
