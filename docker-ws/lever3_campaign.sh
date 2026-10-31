#!/bin/bash
# Lever 3 Run A: plan 399 production call campaign in build/wt-lever3 (Pixel + one headless emulator),
# selected KX rows, then a manual hold for hand-driven legs. Output in the worktree evidence dir.
#   host-run docker-ws/with_native_lease.py <log> -- bash /Volumes/CrucialX9/flutter_app/docker-ws/lever3_campaign.sh
set -uo pipefail
W=/Volumes/CrucialX9/flutter_app/build/wt-lever3
cd "$W" || exit 3
export PATH="$HOME/development/flutter-3.47.2/bin:$HOME/.maestro/bin:/opt/homebrew/bin:$HOME/Library/Android/sdk/platform-tools:$PATH"
export GOTOOLCHAIN=go1.27.1
IP=$(grep -E "^PLAN399_FIXTURE_HOST_IP=" /Volumes/CrucialX9/flutter_app/docker-ws/local_devices.env 2>/dev/null | tail -1 | cut -d= -f2)
[ -n "$IP" ] && export PLAN399_FIXTURE_HOST_IP="$IP"
export RELIABILITY_MULTI_DEVICE_IDS="$(tr -d " \n" < .codex-test-logs/cui-devices.txt)"
export PLAN399_FIXTURE_GO_TIMEOUT=240m
export PLAN399_MANUAL_HOLD_FILE="$W/.codex-test-logs/lever3/manual-hold"
export PLAN399_MANUAL_HOLD_MINUTES="${LEVER3_HOLD_MINUTES:-120}"
[ "${LEVER3_MANUAL_ONLY:-0}" = 1 ] && export PLAN399_MANUAL_ONLY=1
EX=""
for k in kx0020 kx0021 kx0022 kx0023 kx0024 kx0025 kx0026 kx0027 kx0001 kx0029 kx0030; do EX="$EX --exclude $k"; done
echo "start $(date -u +%FT%TZ) head=$(git rev-parse --short HEAD)"
# The lease holder (lever3_lease_until.sh) exits when the automated run ends, so the native lease is
# released while the fixture stays up for hand-driven legs.
MARK="$W/.codex-test-logs/lever3/automated-done"; OUT="$W/.codex-test-logs/lever3/campaign-stdout.log"; rm -f "$MARK"
dart run integration_test/scripts/run_production_audio_call_sims.dart --mode major \
  --scenario android.production_1to1_audio_call --include-regressions --continue-on-failure $EX > "$OUT" 2>&1 &
DP=$!
while kill -0 "$DP" 2>/dev/null; do
  grep -q "PLAN399_MANUAL_HOLD_READY" "$OUT" 2>/dev/null && [ ! -e "$MARK" ] && { touch "$MARK"; echo "automated done $(date -u +%FT%TZ)"; }
  sleep 10
done
wait "$DP"; rc=$?
touch "$MARK"
echo "exit=$rc end=$(date -u +%FT%TZ)"
exit $rc
