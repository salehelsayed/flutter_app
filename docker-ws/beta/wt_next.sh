#!/bin/bash
# Wave 3 "next batch" worktree at .claude/worktrees/wave3-next (git-excluded, hidden from the analyzer,
# outside the SIMS digest roots), so the next batch is written while devices run on the main checkout.
#   wt_next.sh setup              create it on branch wave3-next at the main checkout's HEAD; pub get
#   wt_next.sh flutter <args...>  run the pinned Flutter SDK inside the worktree (host tests, analyze)
#   wt_next.sh sync               cherry-pick wave3-next commits not yet on wave3-baseline-20260930 into the main checkout
#   wt_next.sh git <args...>      git inside the worktree (container git cannot resolve its Mac gitdir)
#   wt_next.sh rebase             move wave3-next onto the main branch tip (after follow-up commits there)
set -uo pipefail
MAIN=/Volumes/CrucialX9/flutter_app; WT=$MAIN/.claude/worktrees/wave3-next; BR=wave3-baseline-20260930
SDK=$HOME/development/flutter-3.47.2
case "${1:-}" in
  setup)
    [ -e "$WT" ] && { echo "exists: $WT"; git -C "$WT" log -1 --format='%h %s'; exit 0; }
    git -C "$MAIN" worktree add -b wave3-next "$WT" "$BR" || exit 1
    for f in .env android/local.properties; do [ -f "$MAIN/$f" ] && cp "$MAIN/$f" "$WT/$f"; done
    cd "$WT" && "$SDK/bin/flutter" pub get >/dev/null 2>&1; echo "pub get rc=$?"; git -C "$WT" log -1 --format='%h %s' ;;
  flutter) shift; cd "$WT" && exec "$SDK/bin/flutter" "$@" ;;
  sync)
    cd "$MAIN" || exit 1
    # Other sessions keep uncommitted edits here (e.g. tool/testing/selection.json), which a cherry-pick refuses
    # to touch. Apply each commit's patch to the index (still HEAD for their files) and to the working files
    # separately, then commit from the index only: their edits stay uncommitted and untouched.
    [ -z "$(git diff --cached --name-only)" ] || { echo "index not empty; stop"; exit 1; }
    for c in $(git rev-list --reverse "$BR..wave3-next"); do
      P=$(mktemp); git diff --binary "$c^" "$c" > "$P"
      git apply --cached "$P" || { echo "INDEX APPLY FAILED at $c"; exit 1; }
      git apply "$P" || { echo "WORKTREE APPLY FAILED at $c (overlaps another session's edit)"; git apply -R --cached "$P"; exit 1; }
      git commit -q -C "$c" || exit 1
    done
    git log -3 --format='%h %s'
    # Drop the now-applied commits from wave3-next so the next sync sends only new ones.
    git -C "$WT" rebase -q "$BR" && echo "worktree rebased onto $BR" ;;
  rebase) git -C "$WT" rebase "$BR" && git -C "$WT" log -1 --format='%h %s' ;;
  git) shift; exec git -C "$WT" "$@" ;;
  *) echo "usage: wt_next.sh setup|flutter|sync|rebase"; exit 2 ;;
esac
