#!/bin/bash
# Wave 5 step 4: preview the canonical full run (plan only, no tests) in the wave3-next worktree. Detached.
#   full_plan.sh [device-config]   Output: docker-ws/beta/wave5/full-plan-<stamp>/ and full_plan.out
if [ -z "${W5P_DETACHED:-}" ]; then
  W5P_DETACHED=1 nohup bash "$0" "$@" >/dev/null 2>&1 &
  echo "started detached (pid $!)"; exit 0
fi
cd /Volumes/CrucialX9/flutter_app/.claude/worktrees/wave3-next || exit 1
export PATH="$HOME/development/flutter-3.47.2/bin:/usr/local/go/bin:/opt/homebrew/bin:$PATH"
D=/Volumes/CrucialX9/flutter_app/docker-ws/beta/wave5
OUT="$D/full-plan-$(date -u +%Y%m%dT%H%M%SZ)"
CFG=()
[ -n "${1:-}" ] && CFG=(--device-config "$1")
{ echo "start $(date -u +%T) $(git log -1 --format=%h) out=$OUT"
  python3 scripts/mknoon_checks.py full --plan --base main "${CFG[@]}" --jobs 3 --flutter-workers 4 --sims-jobs 2 --output "$OUT" 2>&1 | tail -80
  echo "end rc=${PIPESTATUS[0]} $(date -u +%T)"; } > "$D/full_plan.out" 2>&1
