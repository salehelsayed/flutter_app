#!/bin/bash
# Batch-B journeys: generate small synthetic test media (no audio played).
#   host-run bash docker-ws/jb_make_media.sh <out-dir-in-repo>
set -eu
REPO="$(cd "$(dirname "$0")/.." && pwd)"; O="$REPO/$1"; mkdir -p "$O"
F=/opt/homebrew/bin/ffmpeg
:
$F -hide_banner -loglevel error -y -f lavfi -i "testsrc=size=640x360:rate=30:duration=5" -f lavfi -i "anullsrc=r=44100:cl=mono" -i "$O/ovl.png" -filter_complex "[0:v][2:v]overlay=0:0" -shortest -c:v libx264 -pix_fmt yuv420p -c:a aac -b:a 32k -movflags +faststart "$O/jb_test_vid.mp4"
$F -hide_banner -loglevel error -y -f lavfi -i "testsrc=size=1280x720:rate=30:duration=40" -f lavfi -i "anullsrc=r=44100:cl=mono" -shortest -c:v libx264 -b:v 4M -pix_fmt yuv420p -c:a aac -b:a 32k -movflags +faststart "$O/jb_big_vid.mp4"
ls -l "$O"
[ "${2:-}" = big ] && $F -hide_banner -loglevel error -y -f lavfi -i "color=c=gray:s=1280x720:r=30:d=30,noise=alls=80:allf=t" -i "$O/ovl.png" -f lavfi -i "anullsrc=r=44100:cl=mono" -filter_complex "[0:v][1:v]overlay=0:0" -shortest -c:v libx264 -preset ultrafast -b:v 16M -maxrate 16M -bufsize 32M -pix_fmt yuv420p -c:a aac -b:a 32k -movflags +faststart "$O/jb_huge_vid.mp4" && ls -l "$O/jb_huge_vid.mp4"
