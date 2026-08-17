#!/bin/bash
# Cold-launch the app on a given iPhone with --console and stream its stdout
# (Dart print/debugPrint included) to a file on the shared checkout, so the
# container can tail it live. The host bridge buffers long-running command
# output until exit, so streaming through it directly does NOT work — writing
# to a repo file is the working channel (same trick as capture_iphone13_syslog.sh).
# Paths must be host-side: this runs ON THE MAC via host-run.
#   ./docker-ws/capture_iphone_console.sh <udid> [out-file]
DIR="$(cd "$(dirname "$0")" && pwd)"
UDID="${1:?usage: capture_iphone_console.sh <udid> [out-file]}"
# Arg 2 is a BASENAME resolved against this script's own directory — never pass
# an absolute host path from the container, the Mac checkout path is not stable.
OUT="$DIR/${2:-iphone_console_${UDID:0:8}.txt}"
BUNDLE_ID=com.mknoon.app

# `script -q /dev/null` allocates a pty so devicectl's stdout stays LINE buffered.
# Redirecting straight to a file gives 4KB BLOCK buffering, which strands the
# interesting lines in libc until 4096 bytes accumulate (observed 2026-08-16:
# capture froze at exactly one 4KB block while the app was actively logging).
exec script -q /dev/null xcrun devicectl device process launch \
  --device "$UDID" \
  --terminate-existing \
  --console \
  "$BUNDLE_ID" > "$OUT" 2>&1
