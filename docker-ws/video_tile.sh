#!/bin/bash
# Build a small contact sheet (one frame per N seconds, tiled) from a local video.
#   host-run bash docker-ws/video_tile.sh <video> <out-png> <every-seconds> <cols>x<rows>
F=$(command -v ffmpeg || ls /opt/homebrew/bin/ffmpeg /usr/local/bin/ffmpeg 2>/dev/null | head -1)
"$F" -loglevel error -y -i "$1" -vf "fps=1/$3,scale=138:-1,tile=$4" -frames:v 1 "$2" && echo ok
