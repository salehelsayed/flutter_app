#!/bin/bash
# Stream the iPhone 13's syslog to a file on the shared checkout so the
# container can tail it live (the host bridge buffers long-running command
# output until exit, so direct streaming through it doesn't work).
# Paths must be host-side: this runs ON THE MAC via host-run.
DIR="$(cd "$(dirname "$0")" && pwd)"
SYSLOG_BIN="$(command -v idevicesyslog || echo /opt/homebrew/bin/idevicesyslog)"
exec "$SYSLOG_BIN" -u 00008110-00184D622289801E \
  > "$DIR/iphone13_syslog.txt" 2>&1
