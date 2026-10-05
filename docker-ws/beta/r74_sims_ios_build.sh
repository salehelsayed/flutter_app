#!/bin/bash
# Prepare the SIMS ios.simulator.app build in the worktree once, detached and unbounded, so campaigns reuse it.
if [ -z "${R74_DETACHED:-}" ]; then
  R74_DETACHED=1 nohup bash "$0" >/dev/null 2>&1 &
  echo "started detached (pid $!); log docker-ws/beta/r74_sims_ios_build.out"; exit 0
fi
cd /Volumes/CrucialX9/flutter_app/.claude/worktrees/wave3-next || exit 1
export PATH="$HOME/development/flutter-3.47.2/bin:/opt/homebrew/bin:$PATH"
OUT=/Volumes/CrucialX9/flutter_app/docker-ws/beta/r74_sims_ios_build.out
{ echo "start $(date -u +%T)"; dart tool/sims/sims.dart major --only build.ios.simulator.app --format text 2>&1 | tail -30; echo "end rc=${PIPESTATUS[0]} $(date -u +%T)"; ls build/sims/cache; } > "$OUT" 2>&1
