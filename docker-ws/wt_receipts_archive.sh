#!/bin/bash
# Copy .codex-test-logs from build/wt-<name> into the main checkout's .codex-test-logs/archive-<name>/ (no deletes).
#   host-run bash docker-ws/wt_receipts_archive.sh <name>...
R=/Volumes/CrucialX9/flutter_app
for n in "$@"; do
  S="$R/build/$n/.codex-test-logs"; D="$R/.codex-test-logs/archive-$n"
  [ -d "$S" ] || { echo "$n none"; continue; }
  mkdir -p "$D" && cp -Rp "$S"/. "$D"/ && echo "$n copied $(du -sk "$D" | cut -f1)KB"
done
