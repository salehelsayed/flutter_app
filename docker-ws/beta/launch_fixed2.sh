#!/bin/bash
# Start run_fixed2.sh detached from the host bridge (own session), return at once.
H="$(cd "$(dirname "$0")" && pwd)"
nohup perl -e 'use POSIX qw(setsid); setsid(); exec @ARGV' /bin/bash "$H/run_fixed2.sh" \
  > "$H/run_fixed2.out" 2>&1 < /dev/null &
echo "launched pid $!"
