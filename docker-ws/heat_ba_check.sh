#!/bin/bash
# Read-only video check: stream info, frame count, YAVG at 25/50/75% and the frame-to-frame motion (YDIF mean).
REPO="$(cd "$(dirname "$0")/.." && pwd)"; export PATH="/opt/homebrew/bin:$PATH"
for f in "$@"; do F="$REPO/$f"
  info=$(ffprobe -v error -select_streams v:0 -count_frames -show_entries stream=width,height,nb_read_frames:format=duration -of csv=p=0 "$F" | tr '\n' ' ')
  ys=$(ffmpeg -v error -i "$F" -vf "scale=64:-2,signalstats,metadata=print:key=lavfi.signalstats.YAVG:file=-" -f null - 2>/dev/null | sed -n 's/.*YAVG=//p' | awk '{a[NR]=$1} END{printf "%s/%s/%s", a[int(NR*.25)+1], a[int(NR*.5)+1], a[int(NR*.75)+1]}')
  yd=$(ffmpeg -v error -i "$F" -vf "signalstats,metadata=print:key=lavfi.signalstats.YDIF:file=-" -f null - 2>/dev/null | sed -n 's/.*YDIF=//p' | awk '{s+=$1;n++} END{if(n) printf "%.3f", s/n}')
  echo "$f | $info| YAVG(25/50/75%)=$ys | meanYDIF=$yd"
done
# optional: FRAME=1 writes the middle frame as <file>.mid.png (only for Mknoon-only videos)
if [ -n "$FRAME" ]; then for f in "$@"; do ffmpeg -v error -y -ss 4 -i "$REPO/$f" -frames:v 1 -vf scale=390:-2 "$REPO/$f.mid.png"; done; fi
