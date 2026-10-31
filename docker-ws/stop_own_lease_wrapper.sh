#!/bin/bash
# List (no args) or stop (exact PIDs) this session's queued with_native_lease.py wrapper for build-6.
#   host-run bash docker-ws/stop_own_lease_wrapper.sh [pid...]
TAG='with_native_lease.py build/wt-cui-b376/.codex-test-logs/cui-ios-diag-20261021T1656Z/build-6-lease.log'
if [ $# -eq 0 ]; then ps -axo pid=,etime=,args= | grep -F "$TAG" | grep -v grep | cut -c1-200; exit 0; fi
for P in "$@"; do
  [[ "$P" =~ ^[0-9]+$ ]] || continue
  if ps -o args= -p "$P" | grep -qF "$TAG"; then kill -TERM "$P" && echo "stopped $P"; else echo "skip $P (not the wrapper)"; fi
done
