#!/bin/bash
# Count SIMS row results in one log folder: done/pass/fail by exitCode (read-only).
#   bash docker-ws/sims_progress.sh <logs dir> [selected-count]
D="${1:?logs dir}"; N="${2:-}"; cd "$D" || exit 2
p=0; f=0; o=0; for x in *.log; do [ -e "$x" ] || continue; e=$(grep -m1 -oE '^exitCode=-?[0-9]+' "$x" | cut -d= -f2); case "$e" in 0) p=$((p+1));; "") o=$((o+1));; *) f=$((f+1));; esac; done
d=$((p+f)); echo "done=$d pass=$p fail=$f in_progress=$o${N:+ remaining=$((N-d))} latest=$(ls -t | head -1)"
