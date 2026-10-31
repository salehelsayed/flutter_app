#!/bin/bash
# Extract one frame every N seconds from a local video into a private folder (ffmpeg if present, else avconvert-free fallback reports missing).
#   host-run bash docker-ws/video_frames.sh <video> <out-dir> <every-seconds>
F=$(command -v ffmpeg || ls /opt/homebrew/bin/ffmpeg /usr/local/bin/ffmpeg 2>/dev/null | head -1)
[ -z "$F" ] && { echo "ffmpeg missing"; exit 2; }
mkdir -p "$2" && chmod 700 "$2"
"$F" -loglevel error -i "$1" -vf "fps=1/$3,scale=414:-1" "$2/frame_%03d.png" && ls "$2" | wc -l
