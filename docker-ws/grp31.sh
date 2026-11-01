#!/bin/bash
# Lever for the 2026-10-31 P0 GROUP group. Text-only snapshots of the open Mknoon screen on all three members.
#   grp31.sh snap <ID> <tag> [ERE]   write ip11/ip13/emu element lines matching ERE (default p0 test text + media labels) to groups/<ID>/<tag>_*.txt
#   grp31.sh emu <ERE>               emulator texts filtered
export ADB_SERVER_SOCKET=${ADB_SERVER_SOCKET:-tcp:host.docker.internal:5037}
cd "$(dirname "$0")/.." || exit 2
E=.codex-test-logs/p0-phone-20261031/groups
RE='p0|P0|Photo|photo|Video|video|Image|image|Document|document|pdf|PDF|Voice|voice|joined|left|removed|admin|Admin|member|Member|Download|download|unavailable|Failed|Retry|Sending|Uploading|Processing|status'
case "$1" in
  snap)
    D=$E/$2; mkdir -p "$D"; R="${4:-$RE}"; T=$(date -u +%H:%M:%S)
    for p in 11 13; do { echo "# $T UTC"; bash docker-ws/media31.sh isrc $p "$R" | awk -F'|' '{print $1"|"$3"|"$5}'; } > "$D/$3_ip$p.txt"; done
    { echo "# $T UTC"; bash docker-ws/setA_ui.sh texts emulator-5554 | grep -E "$R|mCurrentFocus"; } > "$D/$3_emu.txt"
    for f in "$D/$3"_*.txt; do echo "== $f"; cat "$f"; done ;;
  iview) # iview <11|13> <label substring> <ID> <name>: open media bubble, screenshot only with Mknoon foreground, keep a 300px copy, Back
    B=docker-ws/beta; timeout 120 python3 $B/ap.py "$2" tap "(type == 'XCUIElementTypeImage' OR type == 'XCUIElementTypeButton' OR type == 'XCUIElementTypeStaticText') AND label CONTAINS '$3'" || exit 3; sleep "${6:-4}"
    [ "$(timeout 60 python3 $B/ap.py "$2" app state)" = 4 ] || { echo "not foreground - no shot"; exit 4; }
    timeout 90 python3 $B/ap.py "$2" src 'Back|Image|Video|Play|Pause|Download|unavailable|Failed|p0|P0' | awk -F'|' '{print $1"|"$3"|"$5}' | head -12
    timeout 90 python3 $B/ap.py "$2" shot p0grp_v >/dev/null; F=artifacts/beta-20260928/r2o-shots/p0grp_v_$2.png
    (cd /tmp && python3 -I -c "import sys; sys.path.insert(0,'/tmp/claude-501/-workspace/22b600bc-30a8-40f5-8f72-cbdad6b4916a/scratchpad/qrlib'); from PIL import Image; a=Image.open('/workspace/$F'); a.thumbnail((300,650)); a.save('/workspace/$E/$4/$5.png')"); rm -f "$F"; echo "saved $E/$4/$5.png $(date -u +%T)"
    [ "${7:-back}" = back ] && timeout 60 python3 $B/ap.py "$2" tap "name == 'Back'" >/dev/null ;;
  eview) # eview <ID> <name>: emulator screenshot (Mknoon focus only), 300px copy
    T=/tmp/claude-501/-workspace/22b600bc-30a8-40f5-8f72-cbdad6b4916a/scratchpad/e.png; bash docker-ws/setA_ui.sh shot emulator-5554 $T >/dev/null || exit 4
    (cd /tmp && python3 -I -c "import sys; sys.path.insert(0,'/tmp/claude-501/-workspace/22b600bc-30a8-40f5-8f72-cbdad6b4916a/scratchpad/qrlib'); from PIL import Image; a=Image.open('$T'); a.thumbnail((300,650)); a.save('/workspace/$E/$2/$3.png')"); rm -f $T; echo "saved $E/$2/$3.png" ;;
  istat) # istat <11|13>: screenshot (Mknoon foreground only) -> print image stats of the media area, keep no pixels
    B=docker-ws/beta; [ "$(timeout 60 python3 $B/ap.py "$2" app state)" = 4 ] || { echo "not foreground"; exit 4; }
    timeout 90 python3 $B/ap.py "$2" shot p0grp_s >/dev/null; F=artifacts/beta-20260928/r2o-shots/p0grp_s_$2.png
    (cd /tmp && python3 -I -c "import sys; sys.path.insert(0,'/tmp/claude-501/-workspace/22b600bc-30a8-40f5-8f72-cbdad6b4916a/scratchpad/qrlib'); from PIL import Image, ImageStat; a=Image.open('/workspace/$F').convert('L'); w,h=a.size; c=a.crop((0,int(h*.2),w,int(h*.8))); st=ImageStat.Stat(c); hist=c.histogram(); nb=1-sum(hist[:16])/sum(hist); print('media-area mean=%.1f stddev=%.1f nonblack=%.2f distinct_levels=%d' % (st.mean[0], st.stddev[0], nb, sum(1 for v in hist if v)))"); rm -f "$F" ;;
  estat) # estat: same stats on the emulator screen (Mknoon focus only)
    T=/tmp/claude-501/-workspace/22b600bc-30a8-40f5-8f72-cbdad6b4916a/scratchpad/e.png; bash docker-ws/setA_ui.sh shot emulator-5554 $T >/dev/null || exit 4
    (cd /tmp && python3 -I -c "import sys; sys.path.insert(0,'/tmp/claude-501/-workspace/22b600bc-30a8-40f5-8f72-cbdad6b4916a/scratchpad/qrlib'); from PIL import Image, ImageStat; a=Image.open('$T').convert('L'); w,h=a.size; c=a.crop((0,int(h*.2),w,int(h*.8))); st=ImageStat.Stat(c); hist=c.histogram(); nb=1-sum(hist[:16])/sum(hist); print('media-area mean=%.1f stddev=%.1f nonblack=%.2f distinct_levels=%d' % (st.mean[0], st.stddev[0], nb, sum(1 for v in hist if v)))"); rm -f $T ;;
  emu) bash docker-ws/setA_ui.sh texts emulator-5554 | grep -E "$2" ;;
  *) sed -n 2,4p "$0"; exit 2 ;;
esac
