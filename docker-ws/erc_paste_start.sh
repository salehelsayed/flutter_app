#!/bin/bash
# Discovery-fix proof, early start: Pixel already on the open paste dialog. Set clipboard, paste, submit, then Start at once.
#   df_paste_start.sh <qr-private-file> <label> [cancel|complete]
D="$(dirname "$0")"; A="python3 $D/erc_ap.py px"; S=21071FDF600CSC
adb -s $S shell dumpsys window | grep -q "mCurrentFocus=.*com.mknoon.sims.t011" || { echo "NOT FOREGROUND"; exit 3; }
$A clip "$1" >/dev/null; sleep 1.5
$A tap "desc:Paste migration QR from Clipboard" >/dev/null || exit 2
$A tap "desc:Submit" >/dev/null || exit 2
$A wait "desc:Start transfer" 10 >/dev/null || exit 2
bash "$D/erc_start_timed.sh" "$2" now "${3:-cancel}"
