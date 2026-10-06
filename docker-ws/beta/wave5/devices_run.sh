#!/bin/bash
# Wave 5 step 4 (user choice 2026-10-06): device checks of the full plan of the full plan as a diagnostic --only subset,
# because the full runner gates device campaigns on host checks that cannot pass in this environment.
#   devices_run.sh <check,check,...> [device-config file name] [label]
# Output: .codex-test-logs/production-bootstrap-migration-20260930/wave5-devices-<stamp>/ ; log docker-ws/beta/wave5/devices_run.out
if [ -z "${W5D_DETACHED:-}" ]; then
  W5D_DETACHED=1 nohup bash "$0" "$@" >/dev/null 2>&1 &
  echo "started detached (pid $!)"; exit 0
fi
REPO=/Volumes/CrucialX9/flutter_app/.claude/worktrees/wave3-next
cd "$REPO" || exit 1
export ANDROID_HOME="$HOME/Library/Android/sdk"
export JAVA_HOME=/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home
export PROJECT_MEMORY_TEST_MEMORY_DIR="$HOME/.claude-docker-home/.claude/projects/-workspace/memory"
export MAESTRO_CLI_NO_ANALYTICS=1 MAESTRO_DRIVER_STARTUP_TIMEOUT=240000
SIGNING=/Volumes/CrucialX9/flutter_app/docker-ws/beta/wave4/private/ios-signing-attestation.json
[ -f "$SIGNING" ] && export SIMS_IOS_NOTIFICATION_STAGING_MANIFEST="$SIGNING"
export PATH="$HOME/.maestro/bin:$HOME/development/flutter-3.47.2/bin:/usr/local/go/bin:$ANDROID_HOME/platform-tools:/opt/homebrew/bin:$PATH"
ONLY="$1"; CFGNAME="${2:-wave5-full-device-config.json}"; LABEL="${3:-devices}"
CFGDIR="$REPO/.codex-test-logs/production-bootstrap-migration-20260930"
OUT="$CFGDIR/wave5-$LABEL-$(date -u +%Y%m%dT%H%M%SZ)"
D=/Volumes/CrucialX9/flutter_app/docker-ws/beta/wave5
echo "$OUT" > "$D/devices_run.dir"
{ echo "start $(date -u +%T) $(git log -1 --format=%h) status_lines=$(git status --short | wc -l | tr -d ' ') checks=$(echo "$ONLY" | tr ',' '\n' | wc -l | tr -d ' ') out=$OUT"
  python3 scripts/mknoon_checks.py full --base main --device-config "$CFGDIR/$CFGNAME" \
    --jobs 3 --flutter-workers 4 --sims-jobs 2 --only "$ONLY" --output "$OUT" 2>&1 | tail -150
  echo "end rc=${PIPESTATUS[0]} $(date -u +%T)"; } > "$D/devices_run.out" 2>&1
