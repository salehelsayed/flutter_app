#!/bin/bash
# Create a locked git worktree for one Kayan agent and make it ready for claude-docker.
# Runs on the Mac through host-run.
#   create_agent_worktree.sh <name> <branch>
# Creates ${AGENT_WT_BASE:-/Volumes/CrucialX9}/flutter_app-<name> from origin/main on a new
# branch. AGENT_WT_OVERLAY=<checkout> copies that checkout's launcher and flutter_sdk.sh over
# the new ones (for use before a launcher change reaches main). AGENT_WT_SKIP_PUBGET=1 skips pub get.
set -euo pipefail
NAME="${1:?usage: create_agent_worktree.sh <name> <branch>}"
BRANCH="${2:?usage: create_agent_worktree.sh <name> <branch>}"
MAIN=/Volumes/CrucialX9/flutter_app
WT="${AGENT_WT_BASE:-/Volumes/CrucialX9}/flutter_app-${NAME}"
SDK="${MKNOON_FLUTTER_SDK:-$HOME/development/flutter-3.47.2}"
case "$NAME" in *[!a-z0-9-]*|'') echo "refusing: name must be lowercase letters, digits or dashes"; exit 2;; esac

[ -e "$WT" ] && { echo "refusing: $WT already exists"; exit 2; }
git -C "$MAIN" fetch -q origin main
# No --relative-paths: it adds a repository extension that container git 2.39 rejects.
git -C "$MAIN" worktree add -q -b "$BRANCH" "$WT" origin/main
# Container sessions see this path as missing and would call it "prunable". A lock stops prune.
git -C "$MAIN" worktree lock --reason "claude-docker agent worktree ${NAME}; do not prune" "$WT"

# Local files that git does not track (ignored or in .git/info/exclude).
cd "$MAIN"
PATHS=(
  CLAUDE.md AGENTS.md .agents .codex .claude .env
  android/app/google-services.json android/app/libs android/app/upload-keystore.jks
  android/gradle/wrapper/gradle-wrapper.jar
  android/gradlew android/gradlew.bat android/key.properties android/local.properties
  ios/Runner/GoMknoon.xcframework ios/Runner/GoMknoonNSE.xcframework ios/Runner/GoMknoon.inputs.sha256
  ios/Runner/GoogleService-Info.plist macos/Runner/GoMknoon.xcframework
  graphify-out graphify-arch/graphify-out graphify-arch/tdd-overlay.json
  .graphify-arch-src/graphify-out project-memory/graph.db codex-memory/state
)
EXIST=()
for p in "${PATHS[@]}"; do [ -e "$p" ] && EXIST+=("$p") || echo "skip (missing): $p"; done
rsync -aR \
  --exclude '.claude/worktrees/' --exclude '.claude/scheduled_tasks.*' \
  --exclude '.claude/skills/kayan-launch/state/' \
  --exclude '.DS_Store' --exclude '__pycache__/' \
  "${EXIST[@]}" "$WT/"
echo "copied ${#EXIST[@]} paths"

if [ -n "${AGENT_WT_OVERLAY:-}" ]; then
  cp -p "$AGENT_WT_OVERLAY/scripts/run_claude_docker.sh" "$WT/scripts/run_claude_docker.sh"
  cp -p "$AGENT_WT_OVERLAY/docker-ws/flutter_sdk.sh" "$WT/docker-ws/flutter_sdk.sh"
  echo "overlaid launcher and flutter_sdk.sh from $AGENT_WT_OVERLAY"
fi
grep -q 'KAYAN_AGENT' "$WT/scripts/run_claude_docker.sh" || echo "WARNING: launcher in $WT has no KAYAN_AGENT support yet"
bash -n "$WT/scripts/run_claude_docker.sh" && echo "launcher syntax ok"

if [ "${AGENT_WT_SKIP_PUBGET:-0}" != 1 ]; then
  (cd "$WT" && "$SDK/bin/flutter" pub get >/dev/null 2>&1) && echo "pub get ok" || echo "pub get FAILED"
fi
echo "=== $WT"; git -C "$WT" log -1 --format='%h %s'
if [ -f "$(git -C "$WT" rev-parse --absolute-git-dir)/locked" ]; then echo "locked: 1"; else echo "locked: 0"; fi
echo "tracked changes: $(git -C "$WT" status --porcelain --untracked-files=no | wc -l | tr -d ' ')"
echo CREATE DONE
