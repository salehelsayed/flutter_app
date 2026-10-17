#!/bin/bash
# X1: one SUPPLEMENTAL PRODUCTION / NON-EXCLUSIVE run of the connectivity-restore route
# (android.connectivity_restore_inbox_drain) against the app's compiled production relay defaults,
# on the disposable package only.
#   host-run bash docker-ws/x1_reconnect_supplemental.sh <physical-id> <emulator-id> <report-dir-in-repo> [--dry-run]
set -uo pipefail
cd "$(dirname "$0")/.."
PHYSICAL="${1:?physical device id}"
EMULATOR="${2:?emulator id}"
REPORT_DIR="${3:?report dir}"
MODE="${4:-run}"

export ANDROID_APP_PACKAGE=com.mknoon.sims.connectivity
export SIMS_APP_ID="$ANDROID_APP_PACKAGE"
export ORG_GRADLE_PROJECT_androidApplicationId="$ANDROID_APP_PACKAGE"
bash docker-ws/x1_package_guard.sh || exit 2

relay_default() {
  awk -v name="$1" '$0 ~ "const String " name {getline; print; exit}' lib/core/bridge/p2p_bridge_client.dart \
    | sed -E "s/^[[:space:]]*'([^']+)';.*/\1/"
}
RELAYS="$(relay_default defaultRendezvousAddress),$(relay_default defaultQUICRelayAddress)"
case "$RELAYS" in /dns/*,/dns/*) ;; *) echo "x1: could not read compiled relay defaults" >&2; exit 3 ;; esac

echo "package=$ANDROID_APP_PACKAGE physical=android-physical emulator=android-emulator relay=compiled-production-defaults"
[ "$MODE" = "--dry-run" ] && exit 0

mkdir -p "$REPORT_DIR"
export MKNOON_RELAY_ADDRESSES="$RELAYS"
export SIMS_ANDROID_PHYSICAL_DEVICE_ID="$PHYSICAL"
export SIMS_ANDROID_EMULATOR_DEVICE_ID="$EMULATOR"
export SIMS_PROTECTED_DEVICE_ASSIGNMENTS_JSON="{\"android-emulator\":\"$EMULATOR\",\"android-physical\":\"$PHYSICAL\"}"
export SIMS_REPORT_PATH="$REPORT_DIR/sims-report.json"
dart tool/sims/sims.dart major --only android.connectivity_restore_inbox_drain --continue-on-failure --format json \
  > "$REPORT_DIR/sims.private.log" 2>&1
rc=$?
echo "exit=$rc" >> "$REPORT_DIR/sims.private.log"
exit "$rc"
