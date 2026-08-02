#!/usr/bin/env bash
# Plan 321: per-device iOS install probe — full devicectl output for ONE udid,
# to attribute the real failure cause (the fleet script's message is a guess).
set -uo pipefail
cd "$(dirname "$0")/../.."
UDID="${1:?usage: ios_install_probe_321.sh <udid>}"
APP=build/ios/iphoneos/Runner.app
echo "=== device state ==="
xcrun devicectl list devices | grep -i "$UDID" || echo "NOT IN devicectl LIST"
echo "=== install attempt ==="
xcrun devicectl device install app --device "$UDID" "$APP" 2>&1 | tail -25
