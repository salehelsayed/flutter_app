#!/bin/bash
# VC-014 read-only: per-minute line counts of a capture file (Mac side).   vc014_minute_hist.sh <file-in-repo>
REPO="$(cd "$(dirname "$0")/.." && pwd)"; cut -c1-15 "$REPO/$1" | uniq -c | tail -30
