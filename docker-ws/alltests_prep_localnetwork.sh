#!/bin/bash
# Foreground: Profile-mode Local Network Generated.xcconfig prep in the worktree. Usage: <output label>.
run=/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-run
cd /Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree || exit 4
label="$1"; set --
source "$run/run-env-after-source039.sh" >/dev/null 2>&1
set +euo pipefail
python3 /Volumes/CrucialX9/flutter_app/docker-ws/alltests_prepare_localnetwork.py "$label"
