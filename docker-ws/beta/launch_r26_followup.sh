#!/bin/bash
# launch_r23_validate.sh [case ...] : detached run of r26_followup.sh
H="$(cd "$(dirname "$0")" && pwd)"
nohup perl -e 'use POSIX qw(setsid); setsid(); exec @ARGV' /bin/bash "$H/r26_followup.sh" "$@" \
  > "$H/r26_followup.out" 2>&1 < /dev/null &
echo "r26 followup launched pid $! cases: ${*:-default}"
