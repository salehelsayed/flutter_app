#!/bin/bash
# Usage: android_onboard_only.sh <emulator-serial> <username>; fresh Mknoon onboarding (new identity, mic Not now, notifications Allow)
# and sets the username. Prints the screen texts afterwards.
S="$1"; N="$2"; D="$(dirname "$0")"
t() { bash "$D/pixel_tap_desc.sh" "$S" "$1"; sleep "${2:-3}"; }
t "I'm new here" 4; t "Not now" 3; t 'text="Allow"' 4
t '@Username' 2; adb -s "$S" shell input keyevent 123; for i in $(seq 1 20); do adb -s "$S" shell input keyevent 67; done
adb -s "$S" shell input text "$N"; adb -s "$S" shell input keyevent 66; sleep 3
bash "$D/pixel_ui_texts.sh" "$S" | head -15
