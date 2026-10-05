#!/bin/bash
# Stop this session's Mac-side work: anything running from the wave3-next worktree (warm iOS build,
# campaigns, Maestro/xcodebuild children) and shut down the three disposable simulators.
WT=/Volumes/CrucialX9/flutter_app/.claude/worktrees/wave3-next
pids=$(ps -axo pid=,command= | grep -E "wave3-next|wt_warm_ios_sim|wt_campaign" | grep -v grep | awk '{print $1}')
[ -n "$pids" ] && { echo "stopping: $pids"; kill -TERM $pids 2>/dev/null; sleep 3; kill -KILL $pids 2>/dev/null; } || echo "nothing running from the worktree"
bash /Volumes/CrucialX9/flutter_app/docker-ws/beta/r58_sims_power.sh shutdown
ps -axo pid=,command= | grep -E "wave3-next|mknoon_checks.py run" | grep -v grep | cut -c1-150 || true
