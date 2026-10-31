#!/bin/bash
# Remove the main checkout's index.lock ONLY if it is empty, older than 1 hour and no git process runs on the Mac.
#   host-run bash docker-ws/main_remove_stale_index_lock.sh
L=/Volumes/CrucialX9/flutter_app/.git/index.lock
[ -e "$L" ] || { echo "no index.lock"; exit 0; }
[ "$(stat -f %z "$L")" = 0 ] || { echo "STOP lock not empty"; exit 3; }
age=$(( $(date +%s) - $(stat -f %m "$L") )); [ "$age" -gt 3600 ] || { echo "STOP lock younger than 1 h ($age s)"; exit 4; }
ps -axo command | grep -E '^(/[^ ]*/)?git ' >/dev/null && { echo "STOP a git process is running"; exit 5; }
rm -f "$L" && echo "removed stale index.lock (age ${age}s, empty)"
