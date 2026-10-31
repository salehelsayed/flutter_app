#!/bin/bash
# VC-014 read-only: print production courier failure/connect lines (times only) from the iPhone capture.
REPO="$(cd "$(dirname "$0")/.." && pwd)"
grep -E 'Connection closed production|Connected to courier|Consecutive failures|keepAlive|keep-alive interval|wifiKeepAliveInterval [0-9]+' "$REPO/$1" | grep -E 'production|courier|Consecutive' | cut -c1-22,40-120
