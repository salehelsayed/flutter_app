#!/usr/bin/env bash
# FDC-S6 libp2p-LAN soak capture: stream one device's log to a per-trial file,
# keeping only the win-leg + LAN-discovery + double-delivery lines the soak parses.
#
# Usage:  fdc_s6_capture.sh <android|ios> <udid> <out-dir> [label]
#   e.g.  fdc_s6_capture.sh android 21071FDF600CSC logs/aa pixelA
#         fdc_s6_capture.sh ios 00008110-001… logs/ii iphoneA
#
# Then, on BOTH same-WiFi devices (built --dart-define=FDC_FLOW_LOG=1 with the
# LAN-dial flag + 'p2p_lan_dial' gate ON — see ../README.md §Procedure), compose-
# and-send 1:1 messages back and forth; Ctrl-C when the trial's send batch is done.
#
# The win leg is the receiver's MSG_RECEIVED_TRANSPORT, so capture on the
# RECEIVING device (run on both for a bidirectional trial). The baseline arm
# (LAN-dial flag OFF) MUST capture the SAME lines, else the delta has no baseline.
#
# Requires: adb (Android) / idevicesyslog from libimobiledevice (iOS).
set -euo pipefail

PLATFORM="${1:?usage: fdc_s6_capture.sh <android|ios> <udid> <out-dir> [label]}"
UDID="${2:?usage: fdc_s6_capture.sh <android|ios> <udid> <out-dir> [label]}"
OUTDIR="${3:?usage: fdc_s6_capture.sh <android|ios> <udid> <out-dir> [label]}"
LABEL="${4:-trial}"

mkdir -p "$OUTDIR"
# Stamp from the shell so each trial file is unique (Date.now() folklore avoided).
TS="$(date +%Y%m%d_%H%M%S)"
OUT="$OUTDIR/${LABEL}_${TS}.log"

# Permissive line filter; the parser does the strict JSON extraction. These are
# the five FDC-S6 events: authoritative stored logical outcome, raw arrival leg,
# LAN discovery (carries lanPrivateIp), double delivery, and Go LAN-dial trace.
FILTER='CHAT_MSG_RECEIVE_STORED|MSG_RECEIVED_TRANSPORT|P2P_LAN_PEER_FOUND_REQUEST|CHAT_MSG_DOUBLE_DELIVERY|node:lan_peer_found'

echo "[fdc-s6] capturing ($PLATFORM) → $OUT"
echo "[fdc-s6] NOW: send 1:1 messages between the two same-WiFi devices. Ctrl-C when done."

case "$PLATFORM" in
  android)
    command -v adb >/dev/null 2>&1 || { echo "ERROR: adb not found" >&2; exit 1; }
    adb -s "$UDID" logcat -c >/dev/null 2>&1 || true
    adb -s "$UDID" logcat -v time 2>/dev/null \
      | grep --line-buffered -E "$FILTER" \
      | tee "$OUT"
    ;;
  ios)
    command -v idevicesyslog >/dev/null 2>&1 \
      || { echo "ERROR: idevicesyslog not found. brew install libimobiledevice" >&2; exit 1; }
    idevicesyslog -u "$UDID" 2>/dev/null \
      | grep --line-buffered -E "$FILTER" \
      | tee "$OUT"
    ;;
  *)
    echo "ERROR: platform must be 'android' or 'ios' (got '$PLATFORM')" >&2
    exit 1
    ;;
esac
