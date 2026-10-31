#!/bin/bash
# Discovery-fix proof: from the Pixel Settings screen, open Move account, paste the receiver QR (paste dialog first, clipboard, 4 s wait) and show Confirm the code.
#   df_settings_paste.sh <qr-private-file>
D="$(dirname "$0")"; A="python3 $D/dr_ap.py px"; S=21071FDF600CSC
fg() { adb -s $S shell dumpsys window | grep -q "mCurrentFocus=.*com.mknoon.sims.t011" || { echo "NOT FOREGROUND"; exit 3; }; }
fg; $A tap "desc:Move account to new phone" >/dev/null || exit 2; sleep 2
fg; $A tap "desc:Scan migration QR" >/dev/null || exit 2; sleep 2
fg; $A tap "desc:Paste migration QR" >/dev/null || exit 2; sleep 2
$A clip "$1" >/dev/null; sleep 4
fg; $A tap "desc:Paste migration QR from Clipboard" >/dev/null || exit 2; sleep 1
$A tap "desc:Submit" >/dev/null || exit 2; sleep 2
$A src "Start transfer|^View \|  \| [0-9]{6} " | head -3
