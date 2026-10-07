#!/bin/bash
# Read-only: newest files under the worktree's SIMS logs/proofs/cache, with times.
W=/Volumes/CrucialX9/flutter_app/.claude/worktrees/wave3-next
find "$W/build/sims" -type f -mmin -25 -not -path '*/DerivedData/*' -not -path '*ios-device-production-derived*' -print0 2>/dev/null | xargs -0 ls -lt -D '%H:%M:%S' 2>/dev/null | head -12 | awk '{print $6, $7}' | sed "s#$W/##"
