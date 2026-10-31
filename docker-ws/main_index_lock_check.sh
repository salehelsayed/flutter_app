#!/bin/bash
# Read-only: show the main checkout's index.lock (age) and any running git processes on the Mac.
#   host-run bash docker-ws/main_index_lock_check.sh
L=/Volumes/CrucialX9/flutter_app/.git/index.lock
if [ -e "$L" ]; then stat -f 'index.lock size=%z mtime=%Sm' -t '%Y-%m-%dT%H:%M:%S' "$L"; else echo "no index.lock"; fi
date '+now=%Y-%m-%dT%H:%M:%S'
echo "== git processes"; ps -axo pid,etime,command | grep -E '[g]it ' | cut -c1-140
