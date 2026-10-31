#!/bin/bash
# Read-only: print hw.audioInput / hw.audioOutput for each AVD (config.ini lines only).
#   host-run bash docker-ws/avd_audio_config.sh
for d in "$HOME"/.android/avd/*.avd; do
  n=$(basename "$d" .avd)
  printf '%s: %s\n' "$n" "$(grep -E '^hw\.audio(Input|Output)' "$d/config.ini" 2>/dev/null | tr '\n' ' ')"
done
exit 0
