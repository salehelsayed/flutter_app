#!/bin/bash
# Production bootstrap migration Wave 3 — run the implemented group
# replacement campaigns on the three-Android set: USB Pixel 6 21071FDF600CSC
# (android_physical), emulator-5554 AVD Pixel_7 (android_emulator) and
# emulator-5556 AVD Pixel_6a (android_emulator_second). Must run HOST-side:
#   /claude-host-bin/host-run bash docker-ws/run_wave3_group_campaigns.sh [check,check,...]
# Default: all five implemented Wave 3 checks.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

# The host bridge's PATH has no Maestro or Java; mirror docker-ws/beta/beta_env.sh.
export ANDROID_HOME="$HOME/Library/Android/sdk"
export JAVA_HOME=/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home
export MAESTRO_CLI_NO_ANALYTICS=1
export PATH="$HOME/.maestro/bin:$ANDROID_HOME/platform-tools:/opt/homebrew/bin:$PATH"

CHECKS="${1:-production-group-invites,production-group-create,production-group-reaction,production-group-reaction-toggle,production-group-removed-reaction}"
# Optional second argument: another device config (the four-device set pins android_emulator_third).
DEVICE_CONFIG="${2:-$REPO/.codex-test-logs/production-bootstrap-migration-20260930/wave3-device-config.json}"
OUT="$REPO/.codex-test-logs/production-bootstrap-migration-20260930/wave3-run-$(date -u +%Y%m%dT%H%M%SZ)"
# Compare against main (the pre-baseline commit), as Wave 1/2 did: --only may
# pick only checks that the changes since --base select.
BASE="$(git rev-parse main)"

command -v maestro >/dev/null || { echo "FATAL: maestro not on PATH"; exit 2; }
[ -f "$DEVICE_CONFIG" ] || { echo "FATAL: device config missing: $DEVICE_CONFIG"; exit 2; }

echo "wave3 checks: $CHECKS"
echo "wave3 output: $OUT"
echo "base: $BASE"
exec python3 scripts/mknoon_checks.py run --mode change --base "$BASE" --local \
  --only "$CHECKS" \
  --device-config "$DEVICE_CONFIG" \
  --output "$OUT"
