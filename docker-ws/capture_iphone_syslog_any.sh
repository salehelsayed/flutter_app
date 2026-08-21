#!/bin/bash
# Stream ONE iPhone's syslog to a file in the shared checkout.
#   ./docker-ws/capture_iphone_syslog_any.sh <udid> [out-basename] [process]
#
# Filtered to a single process by default. The unfiltered device firehose is
# ~1 MB/s and repeatedly killed the capture mid-run (2026-08-21); the Runner
# filter keeps every Dart [FLOW] line while cutting volume ~100x.
# Only ONE idevicesyslog may hold the relay per device: strays make a later
# capture connect and then receive nothing. Kill them first.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
UDID="${1:?usage: capture_iphone_syslog_any.sh <udid> [out] [process]}"
OUT="$DIR/${2:-iphone_syslog_${UDID:0:8}.txt}"
PROC="${3:-Runner}"
BIN="$(command -v idevicesyslog || echo /opt/homebrew/bin/idevicesyslog)"
pkill -f "idevicesyslog -u $UDID" 2>/dev/null
sleep 1
exec "$BIN" -u "$UDID" --process "$PROC" > "$OUT" 2>&1
