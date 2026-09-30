#!/bin/bash
# Background: run a docker-ws python helper with cwd = worktree and the run env sourced.
# Usage: <script.py> <label> args...  Log: <run>/<label>.driver.log
run=/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-run
cd /Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree || exit 4
script="$1"; label="$2"; shift 2; args=("$@"); set --
source "$run/run-env-after-source039.sh" >/dev/null 2>&1; set +euo pipefail
nohup python3 "/Volumes/CrucialX9/flutter_app/docker-ws/$script" "$label" "${args[@]}" > "$run/$label.driver.log" 2>&1 < /dev/null &
echo "started pid $!"
