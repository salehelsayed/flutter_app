#!/bin/bash
# Astra call fixes gate: create build/wt-callfix-169 detached at <tip>, rebase <old base>..<tip> onto <new base>
# (aborts and exits 9 on any conflict), copy git-ignored build inputs (Go bindings from build/<binding tree>),
# refresh Go bindings in place, pub get + analyze. Never touches the main checkout's working tree or Astra's worktree.
#   host-run bash docker-ws/callfix_wt_setup.sh <tip> <old base> <new base> <binding tree under build/> <evidence dir under repo>
set -uo pipefail
TIP=${1:?tip}; OLD=${2:?old base}; NEW=${3:?new base}; BT=${4:?binding tree}
REPO=/Volumes/CrucialX9/flutter_app; T=wt-callfix-169; W=$REPO/build/$T
E="$REPO/${5:?evidence}"; mkdir -p "$E"
export PATH="$HOME/development/flutter-3.47.2/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" GOTOOLCHAIN=go1.27.1
cd "$REPO" || exit 2
if [ -d "$W" ]; then
  echo "tree exists head=$(git -C "$W" rev-parse --short HEAD)"
else
  git worktree add --detach "$W" "$TIP" > "$E/wt_add.log" 2>&1; echo "worktree_add exit=$?"
  cd "$W" || exit 2
  git rebase --onto "$NEW" "$OLD" > "$E/rebase.log" 2>&1; rc=$?; echo "rebase exit=$rc"; cat "$E/rebase.log"
  if [ $rc -ne 0 ]; then
    git status --porcelain | head -20; git diff --name-only --diff-filter=U
    git rebase --abort; echo "REBASE CONFLICT (aborted)"; exit 9
  fi
fi
cd "$W" || exit 2
git merge-base --is-ancestor "$NEW" HEAD || { echo "HEAD does not descend from $NEW"; exit 3; }
echo "rebased head=$(git rev-parse HEAD) commits_on_new_base=$(git rev-list --count "$NEW..HEAD")"
git log --format='%h %an | %s' "$NEW..HEAD"
echo "range-diff:"; git range-diff "$OLD..$TIP" "$NEW..HEAD" | cut -c1-160
cd "$REPO" || exit 2
bash "$REPO/docker-ws/wt_inputs_setup.sh" "$T" "$BT" > "$E/inputs.log" 2>&1; echo "inputs exit=$?"; cat "$E/inputs.log"
bash "$REPO/docker-ws/stage_wt_ignored.sh" "$W" "$REPO/build/$BT" > "$E/stage_ignored.log" 2>&1; echo "stage_ignored exit=$?"; cat "$E/stage_ignored.log"
cd "$W" || exit 2
for p in android ios macos; do
  echo "== $p bindings $(date -u +%T)"
  bash scripts/ensure_go_${p}_bindings.sh > "$E/bind_$p.log" 2>&1; echo "$p exit=$?"
done
for f in android/app/libs/GoMknoon.inputs.sha256 ios/Runner/GoMknoon.inputs.sha256; do echo "$(cut -c1-16 "$f") $f"; done
echo "== wt_checks $(date -u +%T)"
bash "$REPO/docker-ws/wt_checks.sh" "$T"
echo "tracked_dirty=$(git status --porcelain --untracked-files=no | wc -l | tr -d ' ') head=$(git rev-parse --short HEAD)"
echo "== done $(date -u +%T)"
