#!/bin/bash
# Create the plan 407 (PDF attachments) git worktree inside the main checkout's
# .claude/worktrees/, so container sessions see it under /workspace. Runs on the
# Mac through host-run.
set -euo pipefail
MAIN=/Volumes/CrucialX9/flutter_app
WT=$MAIN/.claude/worktrees/pdf-407
BRANCH=pdf-attachments-407
SDK="${MKNOON_FLUTTER_SDK:-$HOME/development/flutter-3.47.2}"

[ -e "$WT" ] && { echo "refusing: $WT already exists"; exit 2; }
git -C "$MAIN" worktree add -b "$BRANCH" "$WT" HEAD
# Container sessions cannot resolve the worktree's Mac gitdir and would call it
# "prunable". A lock stops "git worktree prune" from deleting it.
git -C "$MAIN" worktree lock --reason "plan 407 PDF attachments worktree; do not prune" "$WT"

# Local files that git does not track (ignored or in .git/info/exclude).
cd "$MAIN"
PATHS=(
  CLAUDE.md AGENTS.md .claude .env
  android/app/google-services.json android/app/libs
  android/app/src/main/java android/gradle/wrapper/gradle-wrapper.jar
  android/gradlew android/gradlew.bat android/key.properties android/local.properties
  ios/Runner/GoMknoon.xcframework ios/Runner/GoMknoonNSE.xcframework
  ios/Runner/GoogleService-Info.plist macos/Runner/GoMknoon.xcframework
  Test-Flight-Improv/407-pdf-document-attachments-tdd-plan.md
)
EXIST=()
for p in "${PATHS[@]}"; do [ -e "$p" ] && EXIST+=("$p") || echo "skip (missing): $p"; done
rsync -aR \
  --exclude '.claude/worktrees/' --exclude '.claude/scheduled_tasks.*' \
  --exclude '.DS_Store' --exclude '__pycache__/' \
  "${EXIST[@]}" "$WT/"
echo "copied ${#EXIST[@]} paths"

# The Flutter wrapper must run in the checkout that holds it.
python3 - "$WT" <<'PY'
import sys, pathlib
f = pathlib.Path(sys.argv[1]) / "docker-ws/flutter_sdk.sh"
s = f.read_text()
old = "cd /Volumes/CrucialX9/flutter_app\n"
assert s.count(old) == 1
s = s.replace(old, 'cd "$(cd "$(dirname "$0")/.." && pwd)"\n')
f.write_text(s)
print("patched flutter_sdk.sh")
PY

cd "$WT"
"$SDK/bin/flutter" pub get >"$WT/.pubget-407.log" 2>&1 && echo "pub get ok" || { echo "pub get FAILED"; tail -20 "$WT/.pubget-407.log"; }
rm -f "$WT/.pubget-407.log"
echo "=== worktree list ==="; git -C "$MAIN" worktree list
echo "=== wt head ==="; git -C "$WT" log --oneline -1
echo "=== wt status ==="; git -C "$WT" status --short | head
echo CREATE DONE
