#!/bin/bash
# Discovery-fix proof: fresh receiver QR on the simulator (Back, then Move from old phone), decode it privately later.
# Prints the QR-shown time as Pixel-clock epoch.
D="$(dirname "$0")"; B="python3 $D/od_ap.py sim"; S=21071FDF600CSC
$B tap "label == 'Back'" >/dev/null 2>&1; sleep 2
$B tap "label BEGINSWITH 'Move from old phone'" >/dev/null || exit 2
$B wait "label == 'Move Account QR'" 20 >/dev/null || exit 2
echo "qr_shown_epoch=$(adb -s $S shell date +%s.%N | tr -d '\r' | cut -c1-14)"
python3 $D/od_ap.py sim shot "$1" >/dev/null
$B src "Expires|^StaticText \| [0-9]{6} " | cut -d'|' -f2
