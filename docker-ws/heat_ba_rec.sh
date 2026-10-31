#!/bin/bash
# Record the iPhone 13 screen from WDA's MJPEG stream (device port 9100) through a private iproxy port.
#   host-run bash docker-ws/heat_ba_rec.sh <out.mp4 in repo> <seconds>
# Caller must verify Mknoon is foreground first (never record Settings/Home/pickers).
REPO="$(cd "$(dirname "$0")/.." && pwd)"; export PATH="/opt/homebrew/bin:$PATH"
UDID=00008110-00184D622289801E; LP=9213
iproxy $LP:9100 -u $UDID >/dev/null 2>&1 & IP=$!
trap 'kill $IP 2>/dev/null' EXIT
sleep 1.5
ffmpeg -v error -y -f mjpeg -r 10 -i http://127.0.0.1:$LP -t "$2" -vcodec libx264 -pix_fmt yuv420p -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" "$REPO/$1" </dev/null
echo "ffmpeg exit $? -> $1 $(stat -f %z "$REPO/$1" 2>/dev/null) bytes"
