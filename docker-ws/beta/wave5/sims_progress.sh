#!/bin/bash
# Read-only: SIMS capabilities touched since run A began (log files under build/sims/logs and proof attempts).
W=/Volumes/CrucialX9/flutter_app/.claude/worktrees/wave3-next
OUT=$(cat /Volumes/CrucialX9/flutter_app/docker-ws/beta/wave5/devices_run.dir)
echo "logs since start: $(find "$W/build/sims/logs" -type f -newer "$OUT/plan.json" 2>/dev/null | wc -l | tr -d " ")"
find "$W/build/sims/logs" -type f -newer "$OUT/plan.json" -print0 2>/dev/null | xargs -0 ls -t 2>/dev/null | head -8 | sed "s#$W/##"
echo "proof attempts since start:"; find "$W/build/sims/proofs" -maxdepth 2 -type d -name "attempt-*" -newer "$OUT/plan.json" 2>/dev/null | sed "s#$W/build/sims/proofs/##" | head -20
