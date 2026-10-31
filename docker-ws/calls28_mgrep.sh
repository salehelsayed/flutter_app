#!/bin/bash
# Mac-side grep of a live capture file (the container view lags).   host-run bash docker-ws/calls28_mgrep.sh <file-in-repo> <ERE> [max-lines] [width]
REPO="$(cd "$(dirname "$0")/.." && pwd)"; F="$REPO/$1"
echo "now $(date -u +%H:%M:%SZ) lines=$(wc -l < "$F" | tr -d ' ')"
grep -E "$2" "$F" | tail -n "${3:-40}" | cut -c1-"${4:-260}"
