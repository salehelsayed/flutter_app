#!/bin/bash
# Pixel 6, debug Mknoon on the home QR screen: open the scanner, open "Paste QR Data", type the payload file in
# 24-char chunks and Submit, then print the screen texts. Payload is never printed.
export PATH="$HOME/Library/Android/sdk/platform-tools:$PATH"
S=21071FDF600CSC; D="$(dirname "$0")"; F="${1:?payload file}"; P=$(cat "$F")
fg() { adb -s $S shell dumpsys window | grep -q "mCurrentFocus=.*com.mknoon.app" || { echo "NOT FOREGROUND"; exit 3; }; }
fg; bash "$D/pixel_tap_desc.sh" $S "Scan a friend" ; sleep 4
bash "$D/pixel_tap_desc.sh" $S 'text="While using the app"' >/dev/null 2>&1; sleep 3
fg; bash "$D/pixel_tap_desc.sh" $S "Paste QR Data" || exit 2; sleep 2
bash "$D/pixel_tap_desc.sh" $S 'class="android.widget.EditText"' || exit 2; sleep 1
for ((i=0; i<${#P}; i+=24)); do c="${P:i:24}"; adb -s $S shell "input text '${c// /%s}'"; sleep 0.4; done; sleep 1
sleep 1; bash "$D/pixel_tap_desc.sh" $S "Submit"; sleep 1.5; bash "$D/pixel_ui_texts.sh" $S | head -6; sleep 3; bash "$D/pixel_ui_texts.sh" $S | head -6
