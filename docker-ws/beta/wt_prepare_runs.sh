#!/bin/bash
# Make the next-batch worktree a device-run tree: copy the git-ignored build inputs and the Wave 3
# device configs from the main checkout (another session edits the main checkout's sources).
MAIN=/Volumes/CrucialX9/flutter_app; WT=$MAIN/.claude/worktrees/wave3-next
cd "$WT" || exit 1
for f in .env android/key.properties android/local.properties android/app/google-services.json \
         android/app/libs/GoMknoon.aar android/app/libs/GoMknoon.inputs.sha256 tool/build/voice_call_release_defines.json \
         ios/Runner/GoogleService-Info.plist; do
  if [ -f "$MAIN/$f" ] && ! git ls-files --error-unmatch "$f" >/dev/null 2>&1; then
    mkdir -p "$(dirname "$f")"; cp -p "$MAIN/$f" "$f" && echo "copied $f"
  fi
done
# iOS Go bridge (git-ignored; scripts/ensure_go_ios_bindings.sh rebuilds it when its inputs change).
for x in ios/Runner/GoMknoon.xcframework ios/Runner/GoMknoonNSE.xcframework; do
  if [ -d "$MAIN/$x" ] && ! git ls-files --error-unmatch "$x" >/dev/null 2>&1; then
    rm -rf "$x"; cp -Rp "$MAIN/$x" "$x" && echo "copied $x"
  fi
done
for f in ios/Runner/GoMknoon.inputs.sha256 ios/Runner/GoMknoonNSE.inputs.sha256; do
  [ -f "$MAIN/$f" ] && ! git ls-files --error-unmatch "$f" >/dev/null 2>&1 && cp -p "$MAIN/$f" "$f" && echo "copied $f"
done
mkdir -p .codex-test-logs/production-bootstrap-migration-20260930
cp -p "$MAIN"/.codex-test-logs/production-bootstrap-migration-20260930/wave3-device-config*.json .codex-test-logs/production-bootstrap-migration-20260930/ && echo "copied device configs"
echo "status: $(git status --porcelain | wc -l | tr -d ' ') changed paths; head $(git log -1 --format='%h %s' | cut -c1-70)"
# The macOS Go xcframework (git-ignored) for the wake-token binary freshness test.
[ -d "$MAIN/macos/Runner/GoMknoon.xcframework" ] && { rm -rf "$WT/macos/Runner/GoMknoon.xcframework"; cp -Rp "$MAIN/macos/Runner/GoMknoon.xcframework" "$WT/macos/Runner/"; }
