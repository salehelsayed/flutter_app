#!/bin/bash
# Stop run_round2.sh and its Maestro children; restore network, rotation, text size and locale.
. "$(dirname "$0")/beta_env.sh"
pkill -f run_round2.sh; pkill -f "run_flow.sh"; pkill -f "maestro --device"
$ADB shell svc wifi enable; $ADB shell svc data enable
$ADB shell settings put system user_rotation 0; $ADB shell settings put system font_scale 1.0
$ADB shell "cmd locale set-app-locales $PKG --user 0 --locales ''"
xcrun simctl ui "$UDID" content_size large
echo "stopped"
