#!/bin/bash
# Pixel: launch Mknoon and print screen texts after a wait.
export PATH="$HOME/Library/Android/sdk/platform-tools:$PATH"; S=21071FDF600CSC
adb -s $S shell monkey -p com.mknoon.app -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1; sleep ${1:-15}
bash "$(dirname "$0")/pixel_ui_texts.sh" $S | head -14
