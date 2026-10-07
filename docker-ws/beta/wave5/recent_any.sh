#!/bin/bash
# Read-only: newest files anywhere in the worktree (minus heavy build dirs) and /tmp in the last N minutes.
W=/Volumes/CrucialX9/flutter_app/.claude/worktrees/wave3-next
find "$W" /tmp "${TMPDIR:-/tmp}" -type f -mmin -"${1:-35}" -not -path '*DerivedData*' -not -path '*derived*' -not -path '*/cache/*' -not -path '*/.gradle/*' -not -path '*/intermediates/*' -not -path '*/Pods/*' -not -path '*/.dart_tool/*' -print0 2>/dev/null | xargs -0 ls -lt -D '%H:%M:%S' 2>/dev/null | head -14 | awk '{print $6, $5, $7}' | sed "s#$W/##"
