#!/bin/bash
# Explore: run one flow on one device, then dump that device's screen hierarchy.
# Usage: x_dump.sh <ios|android> <flow.yaml> <label> [KEY=VAL ...]
H="$(cd "$(dirname "$0")" && pwd)"
. "$H/beta_env.sh"
DEV=$1; FLOW=$2; L=$3; shift 3
bash "$H/run_flow.sh" "$DEV" "$FLOW" "$L" "$@"
bash "$H/dump_ui.sh" "$L" "$DEV" > /dev/null 2>&1
python3 "$H/ui_summary.py" "$(current_run)/ui/${L}_${DEV}.json" | cut -c1-190 | grep -vE "Battery|Wi-Fi|signal|charging|Security &" | head -${LINES_MAX:-70}
