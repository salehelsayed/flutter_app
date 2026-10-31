#!/bin/bash
# Run one Codex-UI iOS request step in the isolated worktree with the rebound private env (values never printed).
#   host-run bash docker-ws/cui_ios_step.sh <log-relative-to-worktree> -- <command...>
set -uo pipefail
W=/Volumes/CrucialX9/flutter_app/build/wt-cui-b376
R=/Volumes/CrucialX9/flutter_app/build/kayan-safe/codex-ui/plan407-20261021T1507Z/private/runner-rebound
LOG="$1"; shift; [ "$1" = "--" ] && shift
cd "$W" || exit 3
mkdir -p "$(dirname "$LOG")"
eval "$(python3 - "$R/campaign-environment.private.json" <<'PY'
import json,shlex,sys
d=json.load(open(sys.argv[1]))
assert d["SIMS_IOS_PHYSICAL_DEVICE_ID"]=="00008030-001A6D2801BB802E"
for k,v in d.items(): print("export %s=%s" % (k, shlex.quote(str(v))))
PY
)" || { echo "env load failed" > "$LOG"; exit 3; }
export PATH="$HOME/development/flutter-3.47.2/bin:$PATH"
echo "start $(date -u +%FT%TZ) head=$(git rev-parse --short HEAD) cmd=$*" > "$LOG"
"$@" >> "$LOG" 2>&1
rc=$?
echo "exit=$rc end=$(date -u +%FT%TZ)" >> "$LOG"
exit $rc
