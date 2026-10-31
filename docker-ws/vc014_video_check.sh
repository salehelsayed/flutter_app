#!/bin/bash
# Read-only video check on the Mac: duration, size and mean brightness of one middle frame (0 = black).
#   host-run bash docker-ws/vc014_video_check.sh <mp4-in-repo>...
REPO="$(cd "$(dirname "$0")/.." && pwd)"; export PATH="/opt/homebrew/bin:$PATH"
command -v ffmpeg >/dev/null || { echo "no ffmpeg on Mac"; exit 2; }
for f in "$@"; do F="$REPO/$f"
  d=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$F")
  y=$(ffmpeg -v error -ss "$(echo "$d/2" | bc -l)" -i "$F" -frames:v 1 -vf "scale=64:-1,signalstats,metadata=print:key=lavfi.signalstats.YAVG" -f null - 2>&1 | sed -n 's/.*YAVG=//p' | head -1)
  echo "$f duration=${d}s bytes=$(stat -f %z "$F") mid_frame_YAVG=$y"
done
