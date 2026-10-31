#!/bin/bash
# Discovery-fix proof, first-time route: Pixel already on the open "Paste QR Data" dialog. Set clipboard, paste, submit, wait for Confirm.
D="$(dirname "$0")"; A="python3 $D/erc_ap.py px"; S=21071FDF600CSC
adb -s $S shell dumpsys window | grep -q "mCurrentFocus=.*com.mknoon.sims.t011" || { echo "NOT FOREGROUND"; exit 3; }
$A clip "$1" >/dev/null; sleep 1.5
$A tap "desc:Paste from Clipboard" >/dev/null || exit 2
$A tap "desc:Submit" >/dev/null || exit 2
$A wait "desc:Start transfer" 10 >/dev/null || exit 2
$A src "Start transfer|^View \|  \| [0-9]{6} " | head -2
