#!/bin/bash
# launch_r23_validate.sh [case ...] : detached run of run_r24_validate.sh
H="$(cd "$(dirname "$0")" && pwd)"
nohup perl -e 'use POSIX qw(setsid); setsid(); exec @ARGV' /bin/bash "$H/run_r24_validate.sh" "$@" \
  > "$H/run_r24_validate.out" 2>&1 < /dev/null &
echo "r24 validate launched pid $! cases: ${*:-default}"
