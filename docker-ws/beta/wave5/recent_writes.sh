#!/bin/bash
# Read-only: newest files written under the worktree (excluding caches/derived data) in the last N minutes.
W=/Volumes/CrucialX9/flutter_app/.claude/worktrees/wave3-next
find "$W/build" "$W/.codex-test-logs" -type f -mmin -"${1:-30}" -not -path '*DerivedData*' -not -path '*derived*' -not -path '*/cache/*' -not -path '*intermediates*' -print0 2>/dev/null | xargs -0 ls -lt -D '%H:%M:%S' 2>/dev/null | head -10 | awk '{print $6, $5, $7}' | sed "s#$W/##"
