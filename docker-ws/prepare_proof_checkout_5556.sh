#!/bin/bash
# Build an isolated checkout for the six private-media proof runs on
# emulator-5556.
#
# Why a second checkout: /Volumes/CrucialX9/flutter_app is the live tree that
# other sessions edit and run device campaigns from (5554 + the Pixel). Running
# `flutter test -d` from it would share build/ and .dart_tool/ with those runs.
# This copies the CURRENT WORKING TREE (not HEAD) into a sibling directory that
# owns its own build/, .dart_tool/ and log directory.
#
# Run ON THE MAC:
#   /claude-host-bin/host-run bash docker-ws/prepare_proof_checkout_5556.sh
#
# Env:
#   PROOF_DST       destination checkout (default /Volumes/CrucialX9/flutter_app-proof5556)
#   PROOF_MAX_GB    refuse to copy more than this many GB (default 12)
#   PROOF_SKIP_PUB  set to 1 to skip `flutter pub get`
set -uo pipefail

SRC=/Volumes/CrucialX9/flutter_app
DST="${PROOF_DST:-/Volumes/CrucialX9/flutter_app-proof5556}"
MAX_GB="${PROOF_MAX_GB:-8}"

if [ "$DST" = "$SRC" ]; then
  echo "destination must not be the live checkout: $DST" >&2
  exit 2
fi
if [ ! -d "$SRC/integration_test" ]; then
  echo "source checkout looks wrong: $SRC" >&2
  exit 2
fi

SDK="${MKNOON_FLUTTER_SDK:-$HOME/development/flutter-3.47.2}"
FLUTTER="$SDK/bin/flutter"
if [ ! -x "$FLUTTER" ]; then
  echo "flutter sdk not found at $SDK" >&2
  exit 2
fi

echo "=== disk before ==="
df -h "$SRC" | tail -2

EXCLUDES=(
  --exclude '.git/'
  --exclude 'build/'
  --exclude '.dart_tool/'
  --exclude '.gradle/'
  --exclude '.cxx/'
  --exclude 'ios/Pods/'
  --exclude 'macos/Pods/'
  --exclude 'ios/.symlinks/'
  --exclude 'macos/.symlinks/'
  --exclude 'ios/Flutter/ephemeral/'
  --exclude 'macos/Flutter/ephemeral/'
  --exclude '.codex-test-logs/'
  --exclude '.full_regression_logs/'
  # Xcode DerivedData that lives at the repo root, plus other host-only caches.
  # None of it is a build input for an Android `flutter test`.
  --exclude '/CompilationCache.noindex/'
  --exclude '/Index.noindex/'
  --exclude '/ModuleCache.noindex/'
  --exclude '/SDKExplicitPrecompiledModules/'
  --exclude '/SDKStatCaches.noindex/'
  --exclude '/SourcePackages/'
  --exclude '/Logs/'
  --exclude '/.fvm/'
  --exclude '/.claude-host-tmp/'
  --exclude '/.idea/'
  --exclude '/.codex/'
  --exclude '/.tmp_gate/'
  # Evidence/archive trees and tooling that no Android build reads.
  # (artifacts 53 GB, docker-ws 3 GB, SourcePackages 1.6 GB on 2026-09-22.)
  --exclude '/artifacts/'
  --exclude '/docker-ws/'
  --exclude '/backup/'
  --exclude '/graphify-arch/'
  --exclude '/go-relay-server/'
  --exclude '/Test-Flight-Improv/'
  --exclude '/C4/'
  --exclude '.proof-runs/'
  --exclude 'graphify-out/'
  --exclude '.graphify-arch-src/'
  --exclude 'docker-ws/deploy-captures/'
  --exclude 'docker-ws/pixel6-state-guard-backup-*'
  --exclude 'node_modules/'
  --exclude '.venv/'
  --exclude '*.apk'
  --exclude '*.aab'
  --exclude '*.ipa'
  --exclude '*.xcarchive'
  --exclude '*.zip'
  --exclude '*.tar.gz'
)

echo "=== rsync dry run ==="
DRY="$(rsync -a --delete --stats --dry-run "${EXCLUDES[@]}" "$SRC/" "$DST/" 2>&1 | tail -25)"
echo "$DRY" | grep -E "Number of files:|Total file size|Total transferred file size|files to consider" || echo "$DRY" | tail -5

BYTES="$(echo "$DRY" | awk -F': ' '/Total transferred file size/ {gsub(/[^0-9]/, "", $2); print $2}' | tail -1)"
if [ -n "${BYTES:-}" ] && [ "$BYTES" -gt 0 ] 2>/dev/null; then
  GB=$(( BYTES / 1073741824 ))
  echo "planned transfer: ${GB} GB (${BYTES} bytes)"
  if [ "$GB" -gt "$MAX_GB" ]; then
    echo "refusing: planned transfer ${GB} GB exceeds PROOF_MAX_GB=${MAX_GB}" >&2
    exit 3
  fi
fi

echo "=== rsync ==="
# --delete keeps re-runs faithful to the live tree. Excluded paths (build/,
# .dart_tool/) are protected from deletion by rsync unless --delete-excluded is
# given, so the destination keeps its own build outputs across re-syncs.
rsync -a --delete "${EXCLUDES[@]}" "$SRC/" "$DST/"
rc=$?
if [ "$rc" -ne 0 ]; then
  echo "rsync failed rc=$rc" >&2
  exit "$rc"
fi

PROV="$DST/.proof-checkout-provenance.txt"
{
  echo "synced_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "source=$SRC"
  echo "source_head=$(git -C "$SRC" rev-parse HEAD 2>/dev/null)"
  echo "source_head_short=$(git -C "$SRC" rev-parse --short HEAD 2>/dev/null)"
  echo "source_dirty_files=$(git -C "$SRC" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
  echo "note=working tree copy, not a commit; .git deliberately not copied"
} > "$PROV"
echo "=== provenance ==="
cat "$PROV"

if [ "${PROOF_SKIP_PUB:-0}" != "1" ]; then
  echo "=== flutter pub get (in $DST) ==="
  cd "$DST" || exit 2
  "$FLUTTER" pub get 2>&1 | tail -5
  pubrc=${PIPESTATUS[0]}
  echo "pub_get rc=$pubrc"
  if [ "$pubrc" -ne 0 ]; then
    echo "pub get failed; the proof runner needs .dart_tool/package_config.json" >&2
    exit "$pubrc"
  fi
fi

echo "=== disk after ==="
df -h "$DST" | tail -2
echo "PREPARED=$DST"
