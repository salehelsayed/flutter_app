#!/bin/bash
# Pixel: delete N chars in the focused field, tap Submit, print the screen texts.
export PATH="$HOME/Library/Android/sdk/platform-tools:$PATH"; S=21071FDF600CSC; D="$(dirname "$0")"
for i in $(seq 1 "${1:-0}"); do adb -s $S shell input keyevent 67; done; sleep 1
bash "$D/pixel_tap_desc.sh" $S "Submit"; sleep 6; bash "$D/pixel_ui_texts.sh" $S | head -14
