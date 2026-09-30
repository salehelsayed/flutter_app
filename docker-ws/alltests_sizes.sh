#!/bin/bash
# Read-only: non-empty route logs under a label's routes/logs dir.
find "/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-run/$1" -path '*routes/logs/*' -type f -size +0 2>/dev/null | xargs ls -l 2>/dev/null | awk '{print $5, $9}' | head
