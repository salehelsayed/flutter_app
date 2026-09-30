#!/bin/bash
# Extract frames (every N seconds) from a video in docker-ws/.run_handover_copy/xcatt into frames/.
d=/Volumes/CrucialX9/flutter_app/docker-ws/.run_handover_copy/xcatt; v=$(ls "$d"/*.mp4 "$d"/*.mov 2>/dev/null | head -1)
echo "video=$v"; command -v ffmpeg || { echo "no ffmpeg"; exit 1; }
mkdir -p "$d/frames"; ffmpeg -loglevel error -y -i "$v" -vf "fps=1/${1:-5},scale=360:-1" "$d/frames/f%02d.png"; ls "$d/frames"
