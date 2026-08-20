#!/usr/bin/env bash
# Alive-connected durable direct-reaction device leg.
#
# The killed-path leg (android_typed_reaction_smoke, plan 391) proves a killed
# 1:1 recipient IS alerted, but its card comes from the NON-DURABLE FALLBACK:
# the durable arm resolves an exact direct_notification_display_outbox row and
# only the live runtime writes those, so a killed app can never take it. This
# leg keeps the recipient alive and backgrounded, which is where the arm can
# actually execute.
#
# Run from the container as:
#   /claude-host-bin/host-run bash docker-ws/run_durable_reaction_leg.sh
# Output is fully buffered by the bridge, so background it rather than polling.
set -euo pipefail
cd "$(dirname "$0")/.."

SENDER="${SENDER:-21071FDF600CSC}"
RECIPIENT="${RECIPIENT:-emulator-5554}"
ARTIFACT_DIR="${ARTIFACT_DIR:-build/reaction_notification_proof}"

echo "sender=$SENDER recipient=$RECIPIENT artifacts=$ARTIFACT_DIR"
adb devices

exec dart run integration_test/scripts/run_1to1_reaction_notification_device.dart \
  --scenario android_durable_reaction_background_connected \
  --sender "$SENDER" \
  --recipient "$RECIPIENT" \
  --artifact-dir "$ARTIFACT_DIR" \
  --verbose
