#!/bin/bash
# Launch one all-tests checkpoint in the background from the clean worktree.
# Usage: alltests_launch.sh <comma-separated check ids> <new output label> [device-config file in run root]
# Sources the private run env (never printed). Writes <label>.launch.{pid,log} in the run root.
# No `set -u`: the private env scripts reference unset variables.
run=/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-run
wt=/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree
ids="$1"; label="$2"; devcfg="${3:-device-config-next.json}"; nodeps="${4:-}"
echo "start label=$label"
[ -e "$run/$label" ] && { echo "REFUSED: $label exists"; exit 2; }
if pgrep -f "restart-checkpoint.py|alltests_checkpoint.py|scripts/mknoon_checks.py" >/dev/null; then
  echo "REFUSED: another checkpoint is running:"; pgrep -fl "restart-checkpoint.py|alltests_checkpoint.py|scripts/mknoon_checks.py" | cut -c1-200; exit 3
fi
cd "$wt" || { echo "no worktree"; exit 4; }
# run-env-next.sh ends in `exec "$@"`: source it with NO positional args so the
# exec is a no-op, then drop the `set -euo pipefail` it turns on.
set --
source "$run/run-env-after-source039.sh" >/dev/null 2>&1
echo "env sourced rc=$?"
set +euo pipefail
for t in python3 nohup dart flutter xcodebuild adb; do printf 'tool %s: %s\n' "$t" "$(command -v "$t" || echo MISSING)"; done
nohup python3 /Volumes/CrucialX9/flutter_app/docker-ws/alltests_checkpoint.py "$ids" "$label" "$devcfg" $nodeps > "$run/$label.launch.log" 2>&1 < /dev/null &
echo $! > "$run/$label.launch.pid"
echo "LAUNCHED pid=$(cat "$run/$label.launch.pid") label=$label ids=$ids"
