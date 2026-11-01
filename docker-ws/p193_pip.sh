#!/bin/bash
# MEDIA-023 PiP lever for emulator-5554 (UI dump text, dumpsys, and a luminance number from a Mknoon-only screenshot that is deleted at once).
#   p193_pip.sh enter            More actions -> Picture in Picture; prints task mode and app pid
#   p193_pip.sh state            pinned task present? focus, pid
#   p193_pip.sh expand           tap the PiP window, then its centre (fullscreen) control
#   p193_pip.sh look             viewer texts + mean luminance of the video area (0 = black)
#   p193_pip.sh play             tap Play, print position
export ADB_SERVER_SOCKET=${ADB_SERVER_SOCKET:-tcp:host.docker.internal:5037}
cd "$(dirname "$0")" || exit 2
S=emulator-5554; U="bash setA_ui.sh"; A() { timeout 25 adb -s $S "$@"; }
now() { date -u +%H:%M:%S.%3N; }
pinned() { A shell dumpsys activity activities | grep -E 'mode=pinned|windowingMode=pinned' | grep -c mknoon; }
pipbounds() { A shell dumpsys window windows | grep -A40 'ReceivedVideoPictureInPictureActivity' | grep -oE 'frame=\[[0-9,]+\]\[[0-9,]+\]' | head -1 | tr -c '0-9' ' '; }
case "$1" in
  enter)
    $U tap $S 'More actions' >/dev/null; sleep 1.5; $U tap $S 'Picture in Picture'; echo "pip tapped $(now)"; sleep 3
    echo "pinned_tasks=$(pinned) pid=$(A shell pidof com.mknoon.app) focus=$(A shell dumpsys window | grep mCurrentFocus | grep -oE '[a-z0-9.]+/[A-Za-z0-9.]+')" ;;
  state) echo "$(now) pinned_tasks=$(pinned) pid=$(A shell pidof com.mknoon.app) focus=$(A shell dumpsys window | grep mCurrentFocus | grep -oE '[a-z0-9.]+/[A-Za-z0-9.]+')" ;;
  expand)
    read -r a b c d <<<"$(pipbounds)"; [ -n "$d" ] || { echo "NO PIP BOUNDS"; exit 3; }
    x=$(((a+c)/2)); y=$(((b+d)/2)); echo "pip bounds $a,$b $c,$d"
    A shell input tap $x $y; sleep 1.2; A shell input tap $x $y; echo "pip tapped twice at centre $(now)"; sleep 3
    echo "pinned_tasks=$(pinned) focus=$(A shell dumpsys window | grep mCurrentFocus | grep -oE '[a-z0-9.]+/[A-Za-z0-9.]+')" ;;
  look)
    $U texts $S | grep -vE 'introduced|Call back|oice call|Call failed'
    T=/sdcard/p193_l.png; L=/tmp/claude-501/-workspace/22b600bc-30a8-40f5-8f72-cbdad6b4916a/scratchpad/p193_l.png
    $U shot $S "$L" >/dev/null || { echo "no luminance (not Mknoon)"; exit 0; }
    python3 -I -c "
import sys; sys.path.insert(0,'/tmp/claude-501/-workspace/22b600bc-30a8-40f5-8f72-cbdad6b4916a/scratchpad/qrlib')
from PIL import Image, ImageStat
im=Image.open('$L').convert('L'); w,h=im.size; box=im.crop((0,int(h*0.25),w,int(h*0.70)))
print('video-area mean luminance %.1f (0=black), stddev %.1f' % (ImageStat.Stat(box).mean[0], ImageStat.Stat(box).stddev[0]))"
    rm -f "$L" ;;
  play) $U tap $S 'content-desc="Play"'; sleep 1.5; $U texts $S | grep -E ' / |Pause|Play' ;;
  *) sed -n 2,7p "$0"; exit 2 ;;
esac
