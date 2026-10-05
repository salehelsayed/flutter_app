#!/bin/bash
# Create the "fixes" git worktree next to the main checkout and make it ready
# for claude-docker. Runs on the Mac through host-run.
set -euo pipefail
MAIN=/Volumes/CrucialX9/flutter_app
WT=/Volumes/CrucialX9/flutter_app-fixes
SDK="${MKNOON_FLUTTER_SDK:-$HOME/development/flutter-3.47.2}"

[ -e "$WT" ] && { echo "refusing: $WT already exists"; exit 2; }
git -C "$MAIN" worktree add -b fixes "$WT" HEAD
# Container sessions see this path as missing and would call it "prunable".
# A lock stops "git worktree prune" from deleting it.
git -C "$MAIN" worktree lock --reason "claude-docker fixes worktree; do not prune" "$WT"

# Local files that git does not track (ignored or in .git/info/exclude).
cd "$MAIN"
PATHS=(
  CLAUDE.md AGENTS.md .agents .codex .claude .env
  android/app/google-services.json android/app/libs android/app/upload-keystore.jks
  android/app/src/main/java android/gradle/wrapper/gradle-wrapper.jar
  android/gradlew android/gradlew.bat android/key.properties android/local.properties
  ios/Runner/GoMknoon.xcframework ios/Runner/GoMknoonNSE.xcframework
  ios/Runner/GoogleService-Info.plist macos/Runner/GoMknoon.xcframework
  graphify-out graphify-arch/graphify-out graphify-arch/tdd-overlay.json
  .graphify-arch-src/graphify-out project-memory/graph.db codex-memory/state
)
EXIST=()
for p in "${PATHS[@]}"; do [ -e "$p" ] && EXIST+=("$p") || echo "skip (missing): $p"; done
rsync -aR \
  --exclude '.claude/worktrees/' --exclude '.claude/scheduled_tasks.*' \
  --exclude '.DS_Store' --exclude '__pycache__/' \
  "${EXIST[@]}" "$WT/"
echo "copied ${#EXIST[@]} paths"

# Patch the worktree's launcher and Flutter wrapper so they work from a worktree.
python3 - "$WT" <<'PY'
import sys, pathlib
wt = pathlib.Path(sys.argv[1])

p = wt / "scripts/run_claude_docker.sh"
s = p.read_text()
old_log = '  bridge_log="${CLAUDE_DOCKER_HOME}/host-bridge.log"\n'
new_log = ('  bridge_log="${CLAUDE_DOCKER_HOME}/host-bridge.log"\n'
           '  # Each worktree session gets its own log, so two launches do not truncate one file.\n'
           '  if [ -f "${REPO_ROOT}/.git" ]; then\n'
           '    bridge_log="${CLAUDE_DOCKER_HOME}/host-bridge-$(basename "${REPO_ROOT}").log"\n'
           '  fi\n')
assert s.count(old_log) == 1
s = s.replace(old_log, new_log)
anchor = "# Keep Android debug update-installs compatible"
mount = '''# In a git worktree, .git is a file that points into the main checkout's .git
# by its absolute Mac path. Mount that git dir, and the worktree itself, at the
# same Mac paths so git works inside the container.
if [ -f "${REPO_ROOT}/.git" ]; then
  GIT_COMMON_DIR="$(cd "${REPO_ROOT}" && cd "$(git rev-parse --git-common-dir)" && pwd)"
  DOCKER_RUN_ARGS+=(
    -v "${GIT_COMMON_DIR}:${GIT_COMMON_DIR}"
    -v "${REPO_ROOT}:${REPO_ROOT}"
  )
fi

'''
assert s.count(anchor) == 1
s = s.replace(anchor, mount + anchor)
p.write_text(s)

f = wt / "docker-ws/flutter_sdk.sh"
s = f.read_text()
old = "cd /Volumes/CrucialX9/flutter_app\n"
assert s.count(old) == 1
s = s.replace(old, '# Run in the checkout that holds this script (main checkout or a worktree).\ncd "$(cd "$(dirname "$0")/.." && pwd)"\n')
f.write_text(s)
print("patched launcher + flutter_sdk.sh")
PY
bash -n "$WT/scripts/run_claude_docker.sh" && echo "launcher syntax ok"

cd "$WT"
"$SDK/bin/flutter" pub get >"$WT/.claude-host-tmp-pubget.log" 2>&1 && echo "pub get ok" || { echo "pub get FAILED"; tail -20 "$WT/.claude-host-tmp-pubget.log"; }
rm -f "$WT/.claude-host-tmp-pubget.log"
echo "=== worktree list ==="; git -C "$MAIN" worktree list
echo "=== wt status ==="; git -C "$WT" status --short | head
echo CREATE DONE
