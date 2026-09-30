#!/bin/bash
# Background: run focused SIMS capabilities one after another. Usage: <label-prefix> <cap>...
run=/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-run
cd /Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree || exit 4
prefix="$1"; shift; set -- "$@"; caps=("$@"); set --
source "$run/run-env-after-source039.sh" >/dev/null 2>&1; set +euo pipefail
(
  i=0
  for cap in "${caps[@]}"; do
    i=$((i+1)); label="$prefix-$i-${cap##*.}"
    echo "START $label $(date -u +%H:%M:%S)"
    python3 /Volumes/CrucialX9/flutter_app/docker-ws/alltests_sims_focused.py "$label" "$cap"
    echo "END $label $(date -u +%H:%M:%S)"
  done
  echo ALLDONE
) > "$run/$prefix.driver.log" 2>&1 < /dev/null &
echo "driver pid $!"
