#!/usr/bin/env bash
#
# Capture group-send FLOW logs from bob (the Pixel / Android sender) to a
# timestamped file, for debugging the just-joined group-send false-failure
# (Test-Flight-Improv/119-group-send-false-failure-reliability.md).
#
# Prereq: bob has a DEBUG build installed (FLOW logging is gated by kDebugMode,
#         so a profile/release build emits nothing). Install one with:
#             flutter run -d 21071FDF600CSC
#         (leave it running, or detach — adb logcat below works either way).
#
# Usage:  ./scripts/capture_group_send_flow.sh [adb-device-id]
#         Device id defaults to Pixel6 (21071FDF600CSC); override via arg or
#         PIXEL_ID env. Output dir overridable via OUT_DIR env.
#
set -euo pipefail

DEVICE="${1:-${PIXEL_ID:-21071FDF600CSC}}"
OUT_DIR="${OUT_DIR:-/tmp/group-send-flow}"
mkdir -p "$OUT_DIR"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT_FILE="$OUT_DIR/bob_flow_${STAMP}.log"

if ! adb -s "$DEVICE" get-state >/dev/null 2>&1; then
  echo "ERROR: adb device '$DEVICE' not connected. Run 'adb devices' to check." >&2
  exit 1
fi

trap 'echo; echo "Saved: $OUT_FILE"' EXIT

cat <<EOF
Device:  $DEVICE  (bob / sender)
Output:  $OUT_FILE
Filter:  FLOW | publish_debug

>>> Clearing logcat, then streaming. Now run the repro:
    1) alice (iPhone): create a Discussion group, invite bob
    2) bob  (this Pixel): the INSTANT "bob joined the group" shows, send a message
    3) confirm alice received it live; note whether bob shows a clock or red
    4) repeat 3-5x, each with a FRESH group (alice re-creates + re-invites)
>>> Press Ctrl-C when done.

EOF

adb -s "$DEVICE" logcat -c
adb -s "$DEVICE" logcat -v time \
  | grep --line-buffered -E "FLOW|publish_debug" \
  | tee "$OUT_FILE"
