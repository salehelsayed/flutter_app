#!/bin/bash
# Read-only: git status of the main checkout run natively on the Mac (fast), written to a file.
#   host-run bash docker-ws/main_status.sh <out-file-in-repo>
M=/Volumes/CrucialX9/flutter_app; OUT="$M/${1:?out}"
cd "$M" || exit 2
date -u +%T > "$OUT.time"
timeout 900 git status --porcelain=v1 --untracked-files=normal > "$OUT" 2> "$OUT.err"; echo "rc=$? lines=$(wc -l < "$OUT")"
git rev-parse --short HEAD; git rev-parse --abbrev-ref HEAD
date -u +%T >> "$OUT.time"
