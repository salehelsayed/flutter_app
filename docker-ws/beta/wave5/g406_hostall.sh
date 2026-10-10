#!/bin/bash
# Plan 406: full host-all lane in the go-upgrade-406 worktree. Self-detaches.
set -u
W=/Volumes/CrucialX9/flutter_app/docker-ws/beta/wave5
OUT=$W/g406_hostall.log
if [ -z "${G406H_DETACHED:-}" ]; then
  G406H_DETACHED=1 nohup bash "$0" "$@" >"$OUT" 2>&1 &
  echo "detached pid $! log $OUT"; exit 0
fi
export PATH="$HOME/development/flutter-3.47.2/bin:/opt/homebrew/bin:/usr/local/bin:/usr/local/go/bin:$PATH"
cd /Volumes/CrucialX9/flutter_app/.claude/worktrees/go-upgrade-406 || exit 1
date
bash scripts/run_host_test_gates.sh host-all --batch-flutter --concurrency 4 --reporter failures-only
echo "HOSTALL EXIT=$?"; date; echo "HOSTALL DONE"
