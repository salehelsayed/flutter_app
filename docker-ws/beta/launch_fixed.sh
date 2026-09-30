#!/bin/bash
# Start run_fixed.sh detached from the host bridge (own session), return at once.
H="$(cd "$(dirname "$0")" && pwd)"
nohup perl -e 'use POSIX qw(setsid); setsid(); exec @ARGV' /bin/bash "$H/run_fixed.sh" \
  > "$H/run_fixed.out" 2>&1 < /dev/null &
echo "launched pid $!"
