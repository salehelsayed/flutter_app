#!/bin/bash
# run_wave3_group_campaigns.sh, but in the next-batch worktree (isolated from other sessions' edits).
#   wt_campaign.sh <check,check,...> [device-config path inside the worktree]
set -euo pipefail
REPO=/Volumes/CrucialX9/flutter_app/.claude/worktrees/wave3-next
cd "$REPO"
export ANDROID_HOME="$HOME/Library/Android/sdk"
export JAVA_HOME=/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home
export MAESTRO_CLI_NO_ANALYTICS=1
# The Maestro iOS driver can take minutes to start on a loaded Mac (beta_env.sh uses the same value).
export MAESTRO_DRIVER_STARTUP_TIMEOUT=240000
# Wave 4: the central ios.device.production build needs the signing attestation (minted by
# docker-ws/beta/wave4/mint_signing_attestation.sh from the real provisioning profile).
SIGNING=/Volumes/CrucialX9/flutter_app/docker-ws/beta/wave4/private/ios-signing-attestation.json
[ -f "$SIGNING" ] && export SIMS_IOS_NOTIFICATION_STAGING_MANIFEST="$SIGNING"
export PATH="$HOME/.maestro/bin:$ANDROID_HOME/platform-tools:/opt/homebrew/bin:$PATH"
CHECKS="$1"
CFGDIR="$REPO/.codex-test-logs/production-bootstrap-migration-20260930"
DEVICE_CONFIG="${2:-$CFGDIR/wave3-device-config.json}"
OUT="$CFGDIR/wave3-run-$(date -u +%Y%m%dT%H%M%SZ)"
# Change-mode base: docker-ws/beta/wave4/campaign_base (one commit id) when present, else main. After main
# is moved to HEAD, a base of main selects nothing ("Unknown/unselected --only check").
BASE_FILE=/Volumes/CrucialX9/flutter_app/docker-ws/beta/wave4/campaign_base
BASE="$(git rev-parse "$(cat "$BASE_FILE" 2>/dev/null || echo main)")"
command -v maestro >/dev/null || { echo "FATAL: maestro not on PATH"; exit 2; }
[ -f "$DEVICE_CONFIG" ] || { echo "FATAL: device config missing: $DEVICE_CONFIG"; exit 2; }
echo "wave3 (worktree) checks: $CHECKS"; echo "wave3 output: $OUT"; echo "base: $BASE"
exec python3 scripts/mknoon_checks.py run --mode change --base "$BASE" --local \
  --only "$CHECKS" --device-config "$DEVICE_CONFIG" --output "$OUT"
