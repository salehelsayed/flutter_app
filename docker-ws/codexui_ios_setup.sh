#!/bin/bash
# Config-only iOS setup in a Codex-UI worktree for a RunnerTests run: Go iOS bindings (the repo's own script) then pod install.
# Touches only git-ignored outputs (ios/Runner/GoMknoon*.xcframework, ios/Pods). Never reads GoogleService-Info.plist.
#   host-run bash docker-ws/codexui_ios_setup.sh <worktree path> <log file under the flutter_app repo>
set -uo pipefail
W=${1:?worktree}; L="/Volumes/CrucialX9/flutter_app/${2:?log}"; mkdir -p "$(dirname "$L")"
export PATH="$HOME/development/flutter-3.47.2/bin:/opt/homebrew/bin:$PATH"
cd "$W" || exit 2
before=$(git status --porcelain --untracked-files=no | wc -l | tr -d ' ')
{ echo "== go bindings $(date +%T)"; bash scripts/ensure_go_ios_bindings.sh; echo "go_exit=$?"
  echo "== pod install $(date +%T)"; (cd ios && pod install); echo "pod_exit=$?"; echo "== done $(date +%T)"; } > "$L" 2>&1
grep -E "go_exit=|pod_exit=|== done" "$L"
echo "xcframeworks: $(ls -d ios/Runner/*.xcframework 2>/dev/null | xargs -n1 basename | tr '\n' ' ')"
echo "tracked_dirty_before=$before after=$(git status --porcelain --untracked-files=no | wc -l | tr -d ' ')"
git status --porcelain --untracked-files=no | head -5
