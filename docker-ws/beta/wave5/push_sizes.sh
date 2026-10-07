#!/bin/bash
cd /Volumes/CrucialX9/flutter_app || exit 1
for f in $(git diff --name-only origin/wave3-baseline-20260930..HEAD); do [ -f "$f" ] && echo "$(stat -f %z "$f") $f"; done | sort -rn | head -8 | awk '{printf "%8.1f MB  %s\n", $1/1048576, $2}'
