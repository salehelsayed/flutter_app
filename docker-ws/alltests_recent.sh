#!/bin/bash
# Read-only: newest files (with mtime) under a run-root label, and tail of the newest log.
d="/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-run/$1"; date
find "$d" -type f -newermt "-${2:-30} minutes" 2>/dev/null | xargs ls -lt 2>/dev/null | head -8 | awk '{print $6, $7, $8, $5, $9}'
f=$(find "$d" -type f -name '*.log' 2>/dev/null | xargs ls -t 2>/dev/null | head -1); echo "== tail $f"; tail -n 6 "$f" | cut -c1-250
