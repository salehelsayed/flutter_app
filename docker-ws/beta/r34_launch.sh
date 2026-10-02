#!/bin/bash
# r34_launch.sh <script> [args]: detached run of a docker-ws/beta script; output docker-ws/beta/<script>.out
H="$(cd "$(dirname "$0")" && pwd)"; S=$1; shift
nohup perl -e 'use POSIX qw(setsid); setsid(); exec @ARGV' /bin/bash "$H/$S" "$@" > "$H/${S%.sh}.out" 2>&1 < /dev/null &
echo "$S launched pid $! args: ${*:-none}"
