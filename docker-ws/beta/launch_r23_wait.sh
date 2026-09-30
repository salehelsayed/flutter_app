#!/bin/bash
H="$(cd "$(dirname "$0")" && pwd)"
nohup perl -e 'use POSIX qw(setsid); setsid(); exec @ARGV' /bin/bash "$H/r23_wait_then_run.sh" "$@" \
  > "$H/r23_wait_then_run.out" 2>&1 < /dev/null &
echo "r23 wait-then-run launched pid $!"
