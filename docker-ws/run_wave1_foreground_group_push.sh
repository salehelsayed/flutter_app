#!/bin/bash
# Production bootstrap migration Wave 1 — re-run the foreground group-push
# pilot (production.foreground_group_push) on the default Android pair:
# USB Pixel 6 21071FDF600CSC + emulator-5554 (AVD Pixel_7). Uses the same
# ignored device config as the Wave 2 integrated-main campaigns. Must run
# HOST-side: `/claude-host-bin/host-run bash docker-ws/run_wave1_foreground_group_push.sh`.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

DEVICE_CONFIG="$REPO/.codex-test-logs/production-bootstrap-migration-20260928/wave2-continuation-001/provider-device-config-emulator-5554.json"
OUT_ROOT="$REPO/.codex-test-logs/production-bootstrap-migration-20260930"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="$OUT_ROOT/wave1-rerun-$STAMP"
BASE="$(git rev-parse HEAD)"

# The host bridge's PATH has no Maestro or Java; mirror docker-ws/beta/beta_env.sh.
export ANDROID_HOME="$HOME/Library/Android/sdk"
export JAVA_HOME=/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home
export MAESTRO_CLI_NO_ANALYTICS=1
export PATH="$HOME/.maestro/bin:$ANDROID_HOME/platform-tools:/opt/homebrew/bin:$PATH"

command -v maestro >/dev/null || { echo "FATAL: maestro not on PATH"; exit 2; }
[ -f "$DEVICE_CONFIG" ] || { echo "FATAL: device config missing: $DEVICE_CONFIG"; exit 2; }
echo "maestro: $(command -v maestro)"
mkdir -p "$OUT_ROOT"

echo "wave1 output: $OUT"
echo "base: $BASE"
exec python3 scripts/mknoon_checks.py run --mode change --base "$BASE" --local \
  --only production-foreground-group-push \
  --device-config "$DEVICE_CONFIG" \
  --output "$OUT"
