#!/bin/bash
# Start run_round2.sh detached from the host bridge (own session), return at once.
H="$(cd "$(dirname "$0")" && pwd)"
nohup perl -e 'use POSIX qw(setsid); setsid(); exec @ARGV' /bin/bash "$H/run_round2.sh" "$@" \
  > "$H/run_round2.out" 2>&1 < /dev/null &
echo "round2 launched pid $!"
