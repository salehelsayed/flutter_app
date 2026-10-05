#!/bin/bash
# Wave-end host-all in the wave3-next worktree, detached and unbounded. Log: docker-ws/beta/r92_host_all.out
if [ -z "${R92_DETACHED:-}" ]; then
  R92_DETACHED=1 nohup bash "$0" >/dev/null 2>&1 &
  echo "started detached (pid $!)"; exit 0
fi
cd /Volumes/CrucialX9/flutter_app/.claude/worktrees/wave3-next || exit 1
export PATH="$HOME/development/flutter-3.47.2/bin:/usr/local/go/bin:/opt/homebrew/bin:$PATH"
OUT=/Volumes/CrucialX9/flutter_app/docker-ws/beta/r92_host_all.out
{ echo "start $(date -u +%T) $(git log -1 --format=%h)"
  ./scripts/run_host_test_gates.sh host-all --batch-flutter --concurrency 4 --reporter failures-only 2>&1 \
    | tee /Volumes/CrucialX9/flutter_app/docker-ws/beta/r92_host_all.full.log | tail -150
  echo "end rc=${PIPESTATUS[0]} $(date -u +%T)"; } > "$OUT" 2>&1
