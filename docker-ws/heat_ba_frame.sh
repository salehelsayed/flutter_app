#!/bin/bash
# Write frames at 1 s and 7 s of a Mknoon-only video as <file>.t1.png / .t7.png (390 px wide).
REPO="$(cd "$(dirname "$0")/.." && pwd)"; export PATH="/opt/homebrew/bin:$PATH"
for f in "$@"; do for t in 1 7; do ffmpeg -v error -y -ss $t -i "$REPO/$f" -frames:v 1 -vf scale=390:-2 "$REPO/$f.t$t.png"; done; done
