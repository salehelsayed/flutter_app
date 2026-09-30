#!/bin/bash
# Run named curated host checks for uncommitted changes against HEAD.
# Host-side: /claude-host-bin/host-run bash docker-ws/run_host_checks_head.sh <label> <check,check,...>
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"
export ANDROID_HOME="$HOME/Library/Android/sdk"
export JAVA_HOME=/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home
export PATH="$HOME/.maestro/bin:$ANDROID_HOME/platform-tools:/opt/homebrew/bin:$PATH"
OUT="$REPO/.codex-test-logs/production-bootstrap-migration-20260930/$1-$(date -u +%Y%m%dT%H%M%SZ)"
exec python3 scripts/mknoon_checks.py run --mode change --base "$(git rev-parse HEAD)" --local \
  --jobs 3 --flutter-workers 4 --only "$2" --output "$OUT"
