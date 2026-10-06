#!/bin/bash
# Wave 5 step 4: the canonical full run (no --only) on the clean wave3-next worktree. Detached.
# Output: .codex-test-logs/production-bootstrap-migration-20260930/wave5-full-<stamp>/ ; log docker-ws/beta/wave5/full_run.out
if [ -z "${W5F_DETACHED:-}" ]; then
  W5F_DETACHED=1 nohup bash "$0" "$@" >/dev/null 2>&1 &
  echo "started detached (pid $!)"; exit 0
fi
REPO=/Volumes/CrucialX9/flutter_app/.claude/worktrees/wave3-next
cd "$REPO" || exit 1
export ANDROID_HOME="$HOME/Library/Android/sdk"
export JAVA_HOME=/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home
# project-memory tests pin /claude-home (container path); the Mac copy of that folder:
export PROJECT_MEMORY_TEST_MEMORY_DIR="$HOME/.claude-docker-home/.claude/projects/-workspace/memory"
export MAESTRO_CLI_NO_ANALYTICS=1 MAESTRO_DRIVER_STARTUP_TIMEOUT=240000
SIGNING=/Volumes/CrucialX9/flutter_app/docker-ws/beta/wave4/private/ios-signing-attestation.json
[ -f "$SIGNING" ] && export SIMS_IOS_NOTIFICATION_STAGING_MANIFEST="$SIGNING"
export PATH="$HOME/.maestro/bin:$HOME/development/flutter-3.47.2/bin:/usr/local/go/bin:$ANDROID_HOME/platform-tools:/opt/homebrew/bin:$PATH"
CFGDIR="$REPO/.codex-test-logs/production-bootstrap-migration-20260930"
OUT="$CFGDIR/wave5-full-$(date -u +%Y%m%dT%H%M%SZ)"
D=/Volumes/CrucialX9/flutter_app/docker-ws/beta/wave5
echo "$OUT" > "$D/full_run.dir"
{ echo "start $(date -u +%T) $(git log -1 --format=%h) status_lines=$(git status --short | wc -l | tr -d ' ') out=$OUT"
  python3 scripts/mknoon_checks.py full --base main --device-config "$CFGDIR/wave5-full-device-config.json" \
    --jobs 3 --flutter-workers 4 --sims-jobs 2 --output "$OUT" 2>&1 | tail -150
  echo "end rc=${PIPESTATUS[0]} $(date -u +%T)"; } > "$D/full_run.out" 2>&1
