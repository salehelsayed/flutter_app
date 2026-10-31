#!/bin/bash
# Stop one of MY lane runs on the Mac by exact PIDs, only after checking each command line names the expected
# evidence dir or a test binary under it. Children first, then the parent. No pattern kills.
#   host-run bash docker-ws/kill_my_lane_pids.sh <evidence substring> <pid>...
set -u
TAG=${1:?evidence substring}; shift
for p in "$@"; do
  cmd=$(ps -o command= -p "$p" 2>/dev/null)
  [ -n "$cmd" ] || { echo "pid $p gone"; continue; }
  case "$cmd" in
    *"$TAG"*|*relay-server.test*|"go test"*|*"/go test"*|*"go-build"*|*flutter_tester*|*dartvm*|*dartaotruntime*|*flutter_tools*) kill "$p" && echo "TERM $p: ${cmd:0:110}";;
    *) echo "SKIP $p (command does not match): ${cmd:0:110}";;
  esac
done
sleep 3
for p in "$@"; do ps -p "$p" >/dev/null 2>&1 && echo "still alive $p" || echo "gone $p"; done
