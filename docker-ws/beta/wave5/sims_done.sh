#!/bin/bash
# Read-only: capability log files written since run A2 began, with the newest still being written.
W=/Volumes/CrucialX9/flutter_app/.claude/worktrees/wave3-next
OUT=$(cat /Volumes/CrucialX9/flutter_app/docker-ws/beta/wave5/devices_run.dir)
find "$W/build/sims/logs" -maxdepth 1 -type f -name '*.log' -newer "$OUT/plan.json" 2>/dev/null | sed 's#.*/##; s#\.log$##' | sort
