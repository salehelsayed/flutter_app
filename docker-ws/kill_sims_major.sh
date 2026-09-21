#!/bin/bash
# Report or reap the host-side processes started by docker-ws/run_sims_major.sh.
#
#   bash docker-ws/kill_sims_major.sh --list   # report only, kills nothing
#   bash docker-ws/kill_sims_major.sh          # kill them
#
# Deliberately does NOT match its own name (kill_ vs run_).
set -uo pipefail
list_only=0
for arg in "$@"; do
  if [ "$arg" = "--list" ] || [ "$arg" = "--dry-run" ]; then
    list_only=1
  fi
done

for pattern in \
  'docker-ws/run_sims_major.sh' \
  'skills/sims/scripts/run_with_devices.sh' \
  'scripts/run_test_gates.sh sims' \
  'tool/sims/sims.dart'; do
  pids="$(pgrep -f "$pattern" | tr '\n' ' ')"
  if [ -z "${pids// /}" ]; then
    echo "no match  [$pattern]"
  elif [ "$list_only" -eq 1 ]; then
    echo "alive     [$pattern]: $pids"
  else
    echo "killing   [$pattern]: $pids"
    pkill -f "$pattern" || true
  fi
done

if [ "$list_only" -eq 1 ]; then
  exit 0
fi
sleep 2
echo "--- survivors ---"
pgrep -fl 'run_sims_major|run_with_devices|run_test_gates.sh sims|tool/sims/sims.dart' || echo "none"
