#!/bin/bash
# Read-only: age, size and tail of a SIMS capability log (in progress logs included).
W=/Volumes/CrucialX9/flutter_app/.claude/worktrees/wave3-next/build/sims/logs
f=$(ls -t "$W"/$1* 2>/dev/null | head -1); [ -z "$f" ] && { echo "no log for $1"; ls -t "$W" | head -5; exit; }
echo "$f age=$(( $(date +%s) - $(stat -f %m "$f") ))s size=$(stat -f %z "$f")"
tail -c "${2:-1500}" "$f" | grep -av '^\[FLOW\]' | tail -15 | cut -c1-200
