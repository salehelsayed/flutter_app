#!/bin/bash
# X4: one registered iOS notification tap smoke scenario on ONE simulator (local simctl push fixture).
# Result label: local/simulated provider proof (app-delegate presentation and tap routing only).
#   host-run bash docker-ws/x4_ios_notification_sim.sh <simulator-udid> <scenario> <native-selector> <result-dir-in-repo>
set -uo pipefail
cd "$(dirname "$0")/.."
UDID="${1:?simulator udid}"
SCENARIO="${2:?scenario}"
SELECTOR="${3:?native selector}"
RESULT_DIR="${4:?result dir}"
SMOKE="${X4_SMOKE_SCRIPT:-scripts/run_ios_notification_tap_ui_smoke.sh}"

case "$SCENARIO:$SELECTOR" in
  warm:direct_text:testNotificationTap|cold:direct_video:testColdNotificationTap|cold:direct_video:testTapExistingNotification) ;;
  *) echo "x4: refused scenario/selector pair" >&2; exit 2 ;;
esac

mkdir -p "$RESULT_DIR"
bash "$SMOKE" --devices "$UDID" --scenario "$SCENARIO" --native-selector "$SELECTOR" --retries 0 \
  --result-root "$RESULT_DIR" > "$RESULT_DIR/smoke.private.log" 2>&1
rc=$?
echo "exit=$rc" >> "$RESULT_DIR/smoke.private.log"
exit "$rc"
