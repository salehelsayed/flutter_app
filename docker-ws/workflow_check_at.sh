#!/bin/bash
# Run the "workflow" Python check in a clean, temporary worktree at <rev>, outside the repo.
#   host-run bash docker-ws/workflow_check_at.sh <rev> <log file under .codex-test-logs/>
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
REV="${1:?rev}"; LOG="${2:?log}"
[[ "$REV" =~ ^[0-9a-f]{7,40}$ ]] || { echo "invalid rev"; exit 2; }
. "$REPO/docker-ws/_host_paths.sh"
mknoon_require_output "$REPO" "$REPO/$LOG" || exit 2
export PATH="$HOME/development/flutter-3.47.2/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
WT="/Volumes/CrucialX9/flutter_app_wt_workflow_$REV"
git -C "$REPO" worktree add --detach "$WT" "$REV" > /dev/null 2>&1 || { echo "worktree add failed"; exit 2; }
mkdir -p "$(dirname "$REPO/$LOG")"
(
  cd "$WT" || exit 2
  flutter pub get --offline --enforce-lockfile > /dev/null 2>&1; echo "pub get exit=$?"
  FILES=$(python3 -c "import json; print(' '.join(json.load(open('tool/testing/selection.json'))['workflow']['paths']))" 2>/dev/null)
  [ -n "$FILES" ] || FILES=$(python3 -c "
import json; d=json.load(open('tool/testing/selection.json'))
def find(o):
    if isinstance(o, dict):
        w = o.get('workflow')
        if isinstance(w, dict) and 'paths' in w: return w['paths']
        for v in o.values():
            r = find(v)
            if r: return r
print(' '.join(find(d) or []))")
  echo "files: $FILES"
  python3 -m unittest $FILES
) > "$REPO/$LOG" 2>&1
rc=$?
git -C "$REPO" worktree remove --force "$WT" > /dev/null 2>&1
echo "workflow at $REV exit=$rc"; tail -n 3 "$REPO/$LOG"; exit "$rc"
