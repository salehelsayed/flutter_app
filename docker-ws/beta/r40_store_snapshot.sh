#!/bin/bash
# Freeze the live working tree into a temporary git worktree for the store build (1.0.1+121).
# The worktree starts at the live HEAD; rsync then copies every working-tree file over it (tracked edits,
# deletions and untracked files, plus the ignored build inputs such as .env, key.properties, GoMknoon.aar).
set -uo pipefail
SRC=/Volumes/CrucialX9/flutter_app
DST=/Volumes/CrucialX9/flutter_app-store-20261001
REC=$SRC/artifacts/store-build-20261001
SDK=$HOME/development/flutter-3.47.2
cd "$SRC" || exit 1
mkdir -p "$REC"
if [ ! -e "$DST/.git" ]; then
  git worktree add --detach "$DST" HEAD || { echo "FAIL worktree add"; exit 1; }
fi
EX=(--exclude '/.git' --exclude 'build/' --exclude '.dart_tool/' --exclude '.gradle/' --exclude '.cxx/'
  --exclude 'ios/Pods/' --exclude 'macos/Pods/' --exclude 'ios/.symlinks/' --exclude 'macos/.symlinks/'
  --exclude 'ios/Flutter/ephemeral/' --exclude 'macos/Flutter/ephemeral/'
  --exclude '/.codex-test-logs/' --exclude '/.full_regression_logs/' --exclude '/artifacts/'
  --exclude '/CompilationCache.noindex/' --exclude '/Index.noindex/' --exclude '/ModuleCache.noindex/'
  --exclude '/SDKExplicitPrecompiledModules/' --exclude '/SDKStatCaches.noindex/' --exclude '/SourcePackages/'
  --exclude '/Logs/' --exclude '/.claude-host-tmp/' --exclude '/.tmp_gate/' --exclude '/backup/'
  --exclude 'docker-ws/deploy-captures/' --exclude 'docker-ws/pixel6-state-guard-backup-*'
  --exclude 'graphify-out/' --exclude '.graphify-arch-src/' --exclude 'node_modules/' --exclude '.venv/'
  --exclude '*.apk' --exclude '*.aab' --exclude '*.ipa' --exclude '*.xcarchive' --exclude '.proof-runs/')
DRY=$(rsync -a --delete --stats --dry-run "${EX[@]}" "$SRC/" "$DST/" 2>&1)
BYTES=$(echo "$DRY" | awk -F': ' '/Total transferred file size/ {gsub(/[^0-9]/, "", $2); print $2}')
echo "planned transfer bytes=$BYTES"
[ "${BYTES:-0}" -gt 16106127360 ] && { echo "FAIL transfer over 15 GB"; exit 3; }
LIVE_HEAD=$(git rev-parse HEAD); LIVE_DIRTY=$(git status --porcelain | wc -l | tr -d ' ')
rsync -a --delete "${EX[@]}" "$SRC/" "$DST/" || { echo "FAIL rsync"; exit 1; }
cd "$DST" || exit 1
sed -i '' 's/^version: 1\.0\.1+120$/version: 1.0.1+121/' pubspec.yaml
grep -n '^version:' pubspec.yaml
{
  echo "synced_at=$(date '+%Y-%m-%d %H:%M:%S')"
  echo "live_head=$LIVE_HEAD live_dirty_files=$LIVE_DIRTY"
  echo "snapshot_head=$(git rev-parse HEAD) snapshot_dirty_files=$(git status --porcelain | wc -l | tr -d ' ')"
  echo "version=$(grep '^version:' pubspec.yaml)"
} > "$REC/provenance.txt"
git diff --binary HEAD > "$REC/snapshot-tracked.patch"
git ls-files --others --exclude-standard > "$REC/snapshot-untracked-list.txt"
tar czf "$REC/snapshot-untracked.tgz" -T "$REC/snapshot-untracked-list.txt"
cat "$REC/provenance.txt"; ls -la "$REC"
for m in "ios/Runner/AppDelegate.swift:if !Self.firebaseConfigured {" "lib/features/groups/application/drain_group_offline_inbox_use_case.dart:_isV3MissingGroupKeyError" "lib/core/media/m4a_duration.dart:Duration"; do
  f=${m%%:*}; s=${m#*:}; grep -qF "$s" "$f" && echo "marker ok $f" || echo "MARKER MISSING $f"
done
for f in .env android/key.properties android/app/libs/GoMknoon.aar android/app/google-services.json tool/build/voice_call_release_defines.json ios/Runner/GoogleService-Info.plist; do
  [ -f "$f" ] && echo "input ok $f" || echo "INPUT MISSING $f"
done
"$SDK/bin/flutter" pub get 2>&1 | tail -2
echo "R40 DONE"
