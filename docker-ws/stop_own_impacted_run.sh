#!/bin/bash
# Stop exact PIDs of my own impacted-checks run, only if each command line belongs to it.
#   host-run bash docker-ws/stop_own_impacted_run.sh <rev-tag> <pid>...
TAG="${1:?rev tag}"; shift
for pid in "$@"; do
  c=$(ps -o command= -p "$pid")
  case "$c" in
    *run_impacted_checks.sh*"$TAG"*|*mknoon_checks.py\ run*|*flutter_tester*|*dart-sdk/bin/dart*) kill "$pid" && echo "killed $pid";;
    "") echo "gone $pid";;
    *) echo "skip $pid (not mine): ${c:0:80}";;
  esac
done
