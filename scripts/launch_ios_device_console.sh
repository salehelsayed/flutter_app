#!/usr/bin/env bash

set -euo pipefail

if [[ "${1:-}" == "" ]]; then
  cat <<'EOF'
Usage:
  ./scripts/launch_ios_device_console.sh <device-udid> [bundle-id]

Example:
  ./scripts/launch_ios_device_console.sh 00008030-001A6D2801BB802E com.mknoon.app

This cold-launches the installed app on the connected iPhone and attaches its
stdout/stderr to the terminal via `xcrun devicectl ... --console`.
Keep the device unlocked before running it.
EOF
  exit 1
fi

device_udid="$1"
bundle_id="${2:-com.mknoon.app}"

exec xcrun devicectl device process launch \
  --device "$device_udid" \
  --terminate-existing \
  --console \
  "$bundle_id"
