#!/bin/bash
# Read-only probe: does `xcrun devicectl list devices` answer within 30 s? The Mac-side alarm
# guarantees the probe process itself never lingers.
#   host-run bash docker-ws/devicectl_list_probe.sh <out-file-in-repo>
set -u
cd "$(dirname "$0")/.."
OUT="${1:?out file}"
start=$(date +%s)
perl -e 'alarm 30; exec @ARGV' xcrun devicectl list devices > "$OUT" 2>&1
rc=$?
echo "rc=$rc elapsed=$(( $(date +%s) - start ))s" >> "$OUT"
exit "$rc"
