#!/bin/bash
# Stream one device's logcat (from now on, no buffer clear) into a file for a fixed time, then stop it.
# The host bridge holds long-running output until exit, so the file is the live channel.
#   host-run bash docker-ws/logcat_capture_bounded.sh <serial> <out-file> <seconds<=1800>
set -uo pipefail
SERIAL="${1:?serial}"; OUT="${2:?out file}"; SECS="${3:?seconds}"
# Physical serials allowed for capture are listed one per line in a local,
# git-ignored file, so no device ID lives in the repository.
ALLOW="$(dirname "$0")/tmp/physical_serial_allowlist.txt"
[[ "$SERIAL" == emulator-* ]] || { [ -f "$ALLOW" ] && grep -qxF "$SERIAL" "$ALLOW"; } || { echo "refused serial" >&2; exit 2; }
[[ "$SECS" =~ ^[0-9]+$ ]] && [ "$SECS" -le 1800 ] || { echo "refused seconds" >&2; exit 2; }
adb -s "$SERIAL" logcat -v time -T 1 > "$OUT" 2>&1 < /dev/null &
CAPTURE=$!
( sleep "$SECS"; kill "$CAPTURE" 2>/dev/null ) < /dev/null > /dev/null 2>&1 &
TIMER=$!
wait "$CAPTURE"
rc=$?
kill "$TIMER" 2>/dev/null
echo "capture ended rc=$rc after ${SECS}s cap" >> "$OUT"
