#!/bin/bash
# Stream the iPhone 13 Runner syslog into the Group C evidence dir (no pkill: caller checks for strays first).
#   host-run bash docker-ws/astra_c_ios13_syslog.sh <out-name>
OUT=/Volumes/CrucialX9/flutter_app/build/wt-astra-c/.codex-test-logs/astra-c-20261022/${1:?name}
BIN="$(command -v idevicesyslog || echo /opt/homebrew/bin/idevicesyslog)"
exec "$BIN" -u 00008110-00184D622289801E --process Runner > "$OUT" 2>&1
