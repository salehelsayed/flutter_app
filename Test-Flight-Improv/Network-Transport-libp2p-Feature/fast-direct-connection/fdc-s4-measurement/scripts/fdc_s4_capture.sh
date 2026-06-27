#!/usr/bin/env bash
# FDC-S4 device capture: stream the tethered iPhone's Runner log to a file,
# keeping only the pause-flush + background-task lines this spike needs.
#
# Usage:  fdc_s4_capture.sh <iphone-udid> <out-dir> [label]
#   e.g.  fdc_s4_capture.sh 00008110-0011… logs/iphone/n1
#
# Then perform the gesture (compose+send N to an OFFLINE peer, background within
# ~200ms — see ../README.md §Procedure), wait ~15s, and Ctrl-C.
#
# Requires: idevicesyslog (libimobiledevice).  `brew install libimobiledevice`.
set -euo pipefail

UDID="${1:?usage: fdc_s4_capture.sh <iphone-udid> <out-dir> [label]}"
OUTDIR="${2:?usage: fdc_s4_capture.sh <iphone-udid> <out-dir> [label]}"
LABEL="${3:-trial}"

mkdir -p "$OUTDIR"
# No Date.now() folklore here — stamp from the shell so each trial is unique.
TS="$(date +%Y%m%d_%H%M%S)"
OUT="$OUTDIR/${LABEL}_${TS}.log"

if ! command -v idevicesyslog >/dev/null 2>&1; then
  echo "ERROR: idevicesyslog not found. brew install libimobiledevice" >&2
  exit 1
fi

echo "[fdc-s4] capturing → $OUT"
echo "[fdc-s4] NOW: foreground app, send N msgs to an OFFLINE peer, then background within ~200ms."
echo "[fdc-s4] Ctrl-C after ~15s to stop."

# Keep only the lines we parse: native BG_TASK_* and the [FLOW] pause-flush events.
# `--quiet` trims libimobiledevice's own chatter; the grep is a permissive filter
# (the parser does the strict JSON extraction).
idevicesyslog -u "$UDID" 2>/dev/null \
  | grep --line-buffered -E 'BG_TASK_(GRANTED|EXPIRED|REFUSED)|APP_LIFECYCLE_PAUSE_FLUSH_' \
  | tee "$OUT"
