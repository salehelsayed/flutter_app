#!/bin/bash
# Make the P0 media test video on the Mac (labelled frames, 6 s, portrait 720x1280, with a 440 Hz tone) under the evidence folder.
#   host-run bash docker-ws/media31_mkvideo.sh
REPO="$(cd "$(dirname "$0")/.." && pwd)"; D="$REPO/.codex-test-logs/p0-phone-20261031/media/testmedia"
for c in /opt/homebrew/bin/ffmpeg /usr/local/bin/ffmpeg "$(command -v ffmpeg)"; do [ -x "$c" ] && F="$c" && break; done
[ -z "$F" ] && { echo "NO_FFMPEG"; ls /opt/homebrew/bin | grep -iE 'ffm|av' ; exit 3; }
"$F" -y -loglevel error -f lavfi -i "testsrc2=size=720x1280:rate=30:duration=6" -f lavfi -i "sine=frequency=440:duration=6" \
  -vf "drawtext=text='P0 TEST VIDEO 1':fontsize=64:fontcolor=white:box=1:boxcolor=black:x=(w-tw)/2:y=200" \
  -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest "$D/p0_test_video_1.mp4" 2>&1 | tail -3
[ -s "$D/p0_test_video_1.mp4" ] || "$F" -y -loglevel error -f lavfi -i "testsrc2=size=720x1280:rate=30:duration=6" -f lavfi -i "sine=frequency=440:duration=6" -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest "$D/p0_test_video_1.mp4"
ls -l "$D/p0_test_video_1.mp4"
