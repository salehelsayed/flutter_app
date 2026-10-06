#!/bin/bash
# Wave 5 step 4: host-all in the wave3-next worktree, detached. Log: docker-ws/beta/wave5/host_all.out (+ .full.log)
if [ -z "${W5H_DETACHED:-}" ]; then
  W5H_DETACHED=1 nohup bash "$0" >/dev/null 2>&1 &
  echo "started detached (pid $!)"; exit 0
fi
cd /Volumes/CrucialX9/flutter_app/.claude/worktrees/wave3-next || exit 1
export PATH="$HOME/development/flutter-3.47.2/bin:/usr/local/go/bin:/opt/homebrew/bin:$PATH"
D=/Volumes/CrucialX9/flutter_app/docker-ws/beta/wave5
{ echo "start $(date -u +%T) $(git log -1 --format=%h) status_lines=$(git status --short | wc -l | tr -d ' ')"
  ./scripts/run_host_test_gates.sh host-all --batch-flutter --concurrency 4 --reporter failures-only > "$D/host_all.full.log" 2>&1
  rc=$?
  tail -60 "$D/host_all.full.log"
  echo "end rc=$rc $(date -u +%T)"; } > "$D/host_all.out" 2>&1
