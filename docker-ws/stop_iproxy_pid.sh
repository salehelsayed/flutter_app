#!/bin/bash
# Stop one iproxy by exact PID, only if its command line is iproxy. No pattern kills.
#   host-run bash docker-ws/stop_iproxy_pid.sh <pid>
P=${1:?pid}; c=$(ps -o command= -p "$P"); case "$c" in *iproxy*) kill "$P" && echo "stopped $P";; *) echo "refused: $P is not iproxy";; esac
