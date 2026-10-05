#!/bin/bash
# Copy the newest Appium screenshot from the Mac temp dir into artifacts/beta-20260928/r2o-shots/<name>.png
D=/Volumes/CrucialX9/flutter_app/artifacts/beta-20260928/r2o-shots; mkdir -p "$D"
F=$(ls -t /var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/screenshot_*.png 2>/dev/null | head -1)
[ -n "$F" ] || { echo "no screenshot"; exit 1; }
sips -Z 900 "$F" --out "$D/$1.png" >/dev/null 2>&1 || cp "$F" "$D/$1.png"; echo "$D/$1.png"
