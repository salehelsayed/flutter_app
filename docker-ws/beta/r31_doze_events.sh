#!/bin/bash
# Read-only: Doze transitions from the Pixel's events log buffer (since an emulator time, default 14:50), the
# source of the short Doze timings, and FCM/allowlist lines.
. "$(dirname "$0")/beta_env.sh"
SINCE="${1:-09-29 14:50:00.000}"
echo "global device_idle_constants: $($ADB shell settings get global device_idle_constants | tr -d '\r')"
echo "device_config device_idle: $($ADB shell device_config list device_idle 2>/dev/null | tr -d '\r' | tr '\n' ' ' | cut -c1-600)"
echo "events buffer head: $($ADB logcat -b events -d -v threadtime 2>/dev/null | head -2 | tail -1 | cut -c1-40)"
$ADB logcat -b events -d -v threadtime -T "$SINCE" 2>/dev/null | grep -E 'device_idle|screen_toggled|power_screen_state' | cut -c1-140
