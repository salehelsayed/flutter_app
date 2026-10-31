#!/bin/bash
# Read-only: which media tools exist on the Mac.
for t in ffmpeg /opt/homebrew/bin/ffmpeg avconvert say afconvert; do printf '%s: ' "$t"; command -v "$t" || echo none; done
