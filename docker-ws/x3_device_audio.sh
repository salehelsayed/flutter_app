#!/bin/bash
# X3: one run of the device-audio route (android.production_1to1_audio_call) on the disposable
# package only, with the route-owned local Go relay and digest-pinned Docker coturn on the Mac LAN.
# Pre-flight refuses instead of pulling images or reusing leftovers; post-run checks exact cleanup.
#   host-run bash docker-ws/x3_device_audio.sh <physical-id> <emulator-id> <report-dir-in-repo> [--dry-run]
set -uo pipefail
cd "$(dirname "$0")/.."
PHYSICAL="${1:?physical device id}"
EMULATOR="${2:?emulator id}"
REPORT_DIR="${3:?report dir}"
MODE="${4:-run}"
COTURN_IMAGE="coturn/coturn@sha256:aa68aab64a3b929d57fc2924c98ea447bf996cf8dade2508e7b71eaf23f1f14e"

export ANDROID_APP_PACKAGE=com.mknoon.sims.productionaudio
export SIMS_APP_ID="$ANDROID_APP_PACKAGE"
export ORG_GRADLE_PROJECT_androidApplicationId="$ANDROID_APP_PACKAGE"
bash docker-ws/x1_package_guard.sh || exit 2

echo "package=$ANDROID_APP_PACKAGE physical=android-physical emulator=android-emulator relay=local-fixture turn=local-coturn"
[ "$MODE" = "--dry-run" ] && exit 0

mkdir -p "$REPORT_DIR"
PRE="$REPORT_DIR/preflight.txt"
docker info >/dev/null 2>&1 || { echo "preflight: docker daemon not running" | tee "$PRE"; exit 3; }
docker image inspect "$COTURN_IMAGE" >/dev/null 2>&1 || { echo "preflight: pinned coturn image not present (no pull)" | tee "$PRE"; exit 3; }
[ -z "$(docker ps -aq --filter name=mknoon-plan399-coturn-)" ] || { echo "preflight: leftover plan399 coturn container" | tee "$PRE"; exit 3; }
ls -d build/tmp/production-audio-call-fixture-* >/dev/null 2>&1 && { echo "preflight: leftover fixture dir" | tee "$PRE"; exit 3; }
GOTOOLCHAIN=go1.27.1 go version >/dev/null 2>&1 || { echo "preflight: go1.27.1 toolchain unavailable" | tee "$PRE"; exit 3; }
HOST_IP="$(ipconfig getifaddr en0 2>/dev/null)"
[ -n "$HOST_IP" ] || { echo "preflight: no LAN IPv4 on en0" | tee "$PRE"; exit 3; }
echo "preflight: ok" > "$PRE"

export PLAN399_FIXTURE_HOST_IP="$HOST_IP"
export RELIABILITY_MULTI_DEVICE_IDS="$PHYSICAL,$EMULATOR"
export SIMS_ANDROID_PHYSICAL_DEVICE_ID="$PHYSICAL"
export SIMS_ANDROID_EMULATOR_DEVICE_ID="$EMULATOR"
export SIMS_PROTECTED_DEVICE_ASSIGNMENTS_JSON="{\"android-emulator\":\"$EMULATOR\",\"android-physical\":\"$PHYSICAL\"}"
export SIMS_RESERVED_DEVICE_IDS_JSON='[]'
export SIMS_REPORT_PATH="$REPORT_DIR/sims-report.json"
dart run integration_test/scripts/run_production_audio_call_sims.dart --mode major \
  --scenario android.production_1to1_audio_call > "$REPORT_DIR/adapter.private.log" 2>&1
rc=$?
echo "exit=$rc" >> "$REPORT_DIR/adapter.private.log"

containers="$(docker ps -aq --filter name=mknoon-plan399-coturn- | wc -l | tr -d ' ')"
fixture_dirs="$(ls -d build/tmp/production-audio-call-fixture-* 2>/dev/null | wc -l | tr -d ' ')"
{
  echo "containers: $containers"
  echo "fixture dirs: $fixture_dirs"
  echo "go test processes host-wide (not run-attributed, info only): $(ps -axo comm= | awk -F/ '{print $NF}' | grep -cE '\.test$')"
} > "$REPORT_DIR/cleanup.txt"
[ "$rc" = 0 ] && { [ "$containers" != 0 ] || [ "$fixture_dirs" != 0 ]; } && rc=4
exit "$rc"
