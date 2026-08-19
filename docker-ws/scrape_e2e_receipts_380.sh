#!/bin/bash
# Snapshots the installed app's E2E probe receipt off the emulator while the
# plan 380 campaign runs.
#
# The campaign uninstalls `com.mknoon.app` when it exits, which deletes
# app_flutter/intro_e2e_result.json — so a failing probe's own message is gone
# by the time the FAIL verdict is read. The sims verdict only carries
# `errorType=StateError`, which does not say WHICH StateError. This polls the
# file and appends every distinct value it ever holds.
#
# Run HOST-side:
#   /claude-host-bin/host-run bash docker-ws/scrape_e2e_receipts_380.sh
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO/docker-ws/plan380_e2e_receipts.txt"
: > "$OUT"
last=""
end=$(( $(date +%s) + 5400 ))
while [ "$(date +%s)" -lt "$end" ]; do
  cur="$(adb -s emulator-5554 shell run-as com.mknoon.app cat app_flutter/intro_e2e_result.json 2>/dev/null | tr -d '\r')"
  if [ -n "$cur" ] && [ "$cur" != "$last" ]; then
    printf '=== %s ===\n%s\n' "$(date -u +%H:%M:%SZ)" "$cur" >> "$OUT"
    last="$cur"
  fi
  sleep 2
done
