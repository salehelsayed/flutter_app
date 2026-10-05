#!/bin/bash
# Pixel screenshot saved on the Mac: artifacts/beta-20260928/r2o-shots/<name>_px.png
. "$(dirname "$0")/beta_env.sh"
D=/Volumes/CrucialX9/flutter_app/artifacts/beta-20260928/r2o-shots; mkdir -p "$D"
$ADB -s 21071FDF600CSC exec-out screencap -p > "/tmp/$1_px_full.png"
sips -Z 1000 "/tmp/$1_px_full.png" --out "$D/$1_px.png" >/dev/null 2>&1; echo "$D/$1_px.png"
