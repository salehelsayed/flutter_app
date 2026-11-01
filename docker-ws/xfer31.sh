#!/bin/bash
# Lever for the 2026-10-31 P0 ACCOUNT TRANSFER group (two disposable emulators, UI dump text only).
#   xfer31.sh newqr            new phone (5556): Back + "Move from old phone", decode the shown migration QR to the scratchpad, print code/expiry
#   xfer31.sh poster <S> <P> [X0]  tile the decoded QR (size S, period P) into docker-ws/p0grp_poster.png (old phone back camera)
#   xfer31.sh scan [secs]      old phone (5554): close + reopen the migration scanner, poll texts until it changes
#   OLD=<serial> NEW=<serial> swap roles (default old 5554, new 5556)
export ADB_SERVER_SOCKET=${ADB_SERVER_SOCKET:-tcp:host.docker.internal:5037}
cd "$(dirname "$0")/.." || exit 2
SP=/tmp/claude-501/-workspace/22b600bc-30a8-40f5-8f72-cbdad6b4916a/scratchpad; U="bash docker-ws/setA_ui.sh"; O=${OLD:-emulator-5554}; N=${NEW:-emulator-5556}
case "$1" in
  newqr)
    $U tap $N 'content-desc="Back"' >/dev/null; sleep 3; $U tap $N 'Move from old phone' >/dev/null; sleep 6
    $U texts $N | grep -E '^content-desc="[0-9]{6}"|Expires'
    $U shot $N $SP/q.png >/dev/null || exit 4
    (cd /tmp && python3 -I -c "import sys; sys.path.insert(0,'$SP/qrlib'); import zxingcpp, json; from PIL import Image; t=zxingcpp.read_barcodes(Image.open('$SP/q.png'))[0].text; open('$SP/mig_qr.txt','w').write(t); print('qr', json.loads(t)['kind'], len(t))")
    rm -f $SP/q.png; date -u +%T ;;
  poster) (cd /tmp && python3 -I $SP/mkposter_tile.py $SP/mig_qr.txt "$2" "$3" "${4:-0}") ;;
  scan)
    adb -s $O shell input keyevent 4; sleep 2
    $U tap $O 'content-desc="Scan migration QR"' >/dev/null || $U tap $O 'content-desc="Scan again"' >/dev/null || { echo "no scan button"; exit 3; }
    for i in $(seq 1 $(( ${2:-20} / 4 ))); do sleep 4; X=$($U texts $O | sed -n 2,20p); echo "$X" | grep -q 'Point your camera' || { echo "$(date -u +%T)"; echo "$X"; exit 0; }; done; echo "no decode $(date -u +%T)" ;;
  *) sed -n 2,5p "$0"; exit 2 ;;
esac
