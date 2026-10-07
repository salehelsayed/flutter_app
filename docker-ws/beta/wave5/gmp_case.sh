#!/bin/bash
# Read-only: newest multi-party case dir in TMPDIR: file list and the tail of each role log.
d=$(ls -dt "${TMPDIR:-/tmp}"/group_multi_party_* 2>/dev/null | head -1); echo "$d"
ls -lt -D "%H:%M:%S" "$d" | head -8 | awk "{print \$6, \$7}"
for r in alice bob charlie dana; do f="$d/$r.log"; [ -f "$f" ] && { echo "== $r ($(stat -f %z "$f") bytes)"; grep -av "^\[FLOW\]" "$f" | tail -4 | cut -c1-200; }; done
