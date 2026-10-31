#!/bin/bash
# Translate-preview gate: create build/wt-translate-main detached at <rev>, copy the git-ignored build inputs
# (from the main checkout; Go bindings from build/<binding tree>), refresh Go bindings in place, pub get + analyze.
# Never touches the main checkout's working tree. Prints sha prefixes only.
#   host-run bash docker-ws/translate_main_wt_setup.sh <rev> <binding tree under build/> <evidence dir under repo>
set -uo pipefail
REV=${1:?rev}; BT=${2:?binding tree}; REPO=/Volumes/CrucialX9/flutter_app; T=wt-translate-main; W=$REPO/build/$T
E="$REPO/${3:?evidence}"; mkdir -p "$E"
export PATH="$HOME/development/flutter-3.47.2/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" GOTOOLCHAIN=go1.27.1
cd "$REPO" || exit 2
if [ -d "$W" ]; then
  echo "tree exists head=$(git -C "$W" rev-parse --short HEAD)"
else
  git worktree add --detach "$W" "$REV" > "$E/wt_add.log" 2>&1; echo "worktree_add exit=$?"
fi
[ "$(git -C "$W" rev-parse HEAD)" = "$(git rev-parse "$REV")" ] || { echo "HEAD MISMATCH"; exit 3; }
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
