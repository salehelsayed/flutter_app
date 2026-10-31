#!/bin/bash
# Pixel 6: launch Mknoon and run the standard fresh onboarding with the given username.
export PATH="$HOME/Library/Android/sdk/platform-tools:$PATH"
S=21071FDF600CSC; D="$(dirname "$0")"
adb -s $S shell monkey -p com.mknoon.app -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1; sleep 12
bash "$D/pixel_ui_texts.sh" $S | head -8
bash "$D/android_onboard_only.sh" $S "${1:?username}"
