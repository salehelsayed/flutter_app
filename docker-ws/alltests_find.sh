#!/bin/bash
# Read-only: find files under a run-root label matching a name pattern (newest first).
find "/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-run/$1" -type f -iname "$2" 2>/dev/null | xargs ls -lt 2>/dev/null | head -${3:-10} | awk '{print $5, $6, $7, $8, $9}'
