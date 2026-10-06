#!/bin/bash
# Read-only: per production capability attempted in run A, PASS (no first-failure, cleanup PASS), FAIL (first-failure.txt) or OPEN.
W=/Volumes/CrucialX9/flutter_app/.claude/worktrees/wave3-next
OUT=$(cat /Volumes/CrucialX9/flutter_app/docker-ws/beta/wave5/devices_run.dir)
for d in $(find "$W/build/sims/proofs" -maxdepth 2 -type d -name "attempt-*" -newer "$OUT/plan.json" 2>/dev/null); do
  cap=$(basename "$(dirname "$d")")
  if [ -f "$d/first-failure.txt" ]; then s="FAIL $(head -c 140 "$d/first-failure.txt" | tr "\n" " ")"
  elif [ -f "$d/cleanup.json" ] && grep -q "\"status\": *\"PASS\"" "$d/cleanup.json"; then s=PASS
  else s=OPEN; fi
  echo "$s | $cap"
done | sort
