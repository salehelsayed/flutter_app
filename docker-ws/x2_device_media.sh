#!/bin/bash
# X2: one run of the device-media route (android.direct_media_blob_custody) on the disposable
# package only, with the route-owned local Go relay fixture on the Mac LAN.
#   host-run bash docker-ws/x2_device_media.sh <physical-id> <emulator-id> <report-dir-in-repo> [--dry-run]
set -uo pipefail
cd "$(dirname "$0")/.."
PHYSICAL="${1:?physical device id}"
EMULATOR="${2:?emulator id}"
REPORT_DIR="${3:?report dir}"
MODE="${4:-run}"

export ANDROID_APP_PACKAGE=com.mknoon.sims.directmedia
export SIMS_APP_ID="$ANDROID_APP_PACKAGE"
export ORG_GRADLE_PROJECT_androidApplicationId="$ANDROID_APP_PACKAGE"
bash docker-ws/x1_package_guard.sh || exit 2

echo "package=$ANDROID_APP_PACKAGE physical=android-physical emulator=android-emulator relay=local-fixture"
[ "$MODE" = "--dry-run" ] && exit 0

HOST_IP="$(ipconfig getifaddr en0 2>/dev/null)"
[ -n "$HOST_IP" ] || { echo "x2: no LAN IPv4 on en0" >&2; exit 3; }

mkdir -p "$REPORT_DIR"
export PLAN347_FIXTURE_HOST_IP="$HOST_IP"
export GOTOOLCHAIN=go1.27.1
export RELIABILITY_MULTI_DEVICE_IDS="$PHYSICAL,$EMULATOR"
export SIMS_ANDROID_PHYSICAL_DEVICE_ID="$PHYSICAL"
export SIMS_ANDROID_EMULATOR_DEVICE_ID="$EMULATOR"
export SIMS_PROTECTED_DEVICE_ASSIGNMENTS_JSON="{\"android-emulator\":\"$EMULATOR\",\"android-physical\":\"$PHYSICAL\"}"
export SIMS_RESERVED_DEVICE_IDS_JSON='[]'
export SIMS_REPORT_PATH="$REPORT_DIR/sims-report.json"
dart run integration_test/scripts/run_direct_media_blob_custody_sims.dart --mode major \
  --scenario android.direct_media_blob_custody > "$REPORT_DIR/adapter.private.log" 2>&1
rc=$?
echo "exit=$rc" >> "$REPORT_DIR/adapter.private.log"
# Leftover check (names only): the adapter's fallback stops `go`, not its compiled test binary.
ps -axo comm= | awk -F/ '{print $NF}' | grep -E '\.test$|^go$' | sort | uniq -c > "$REPORT_DIR/leftover-go-processes.txt"
exit "$rc"
