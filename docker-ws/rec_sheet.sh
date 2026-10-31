#!/bin/bash
# Contact sheet from an existing recording: <mp4 under repo> <start s> <dur s> <fps> <out png under repo>
R=/Volumes/CrucialX9/flutter_app
/opt/homebrew/bin/ffmpeg -loglevel error -y -ss "${2:?}" -t "${3:?}" -i "$R/${1:?}" -vf "fps=${4:?},scale=270:-1,tile=8x2" -frames:v 1 "$R/${5:?}"; /opt/homebrew/bin/ffprobe -v error -show_entries format=duration -of csv=p=0 "$R/$1"
