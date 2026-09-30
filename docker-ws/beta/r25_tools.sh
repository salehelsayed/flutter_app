#!/bin/bash
# Read-only: tools available on the Mac for video checks.
for t in ffmpeg ffprobe; do printf "%s: " $t; (command -v $t || ls /opt/homebrew/bin/$t /usr/local/bin/$t 2>/dev/null | head -1 || echo missing); done
/opt/homebrew/bin/ffmpeg -version 2>/dev/null | head -1
