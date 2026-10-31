#!/bin/bash
# Stop only the queued release-126 lease wrapper (exact PID after a command check).
# A wrapper that already holds the lease (build.log exists) is left alone.
set -uo pipefail
L=/Volumes/CrucialX9/flutter_app/build/wt-release-126/.codex-test-logs/release-126/build.log
if [ -f "$L" ]; then echo "REFUSE build.log exists, wrapper may hold the lease"; exit 1; fi
ps -axo pid=,args= | while read -r pid args; do
  case "$args" in
    *with_native_lease.py\ build/wt-release-126/.codex-test-logs/release-126/build.log*)
      echo "match pid=$pid"; kill "$pid" && echo "stopped pid=$pid";;
  esac
done
sleep 1
ps -axo pid=,args= | grep -c 'with_native_lease.py build/wt-release-126' | sed 's/^/remaining_incl_grep=/'
