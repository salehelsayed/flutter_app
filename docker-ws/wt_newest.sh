#!/bin/bash
# Read-only: newest file mtime (excluding build outputs) in given worktrees under build/.
cd /Volumes/CrucialX9/flutter_app/build || exit 2
for w in "$@"; do m=$(find "$w" -type f -not -path "*/build/*" -not -path "*/.dart_tool/*" -newermt "-36 hours" 2>/dev/null | head -200 | xargs stat -f "%m" 2>/dev/null | sort -n | tail -1); echo "$w newest=$( [ -n "$m" ] && date -r $m +%m-%dT%H:%M || echo older-than-36h)"; done
