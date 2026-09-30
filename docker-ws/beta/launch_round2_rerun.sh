#!/bin/bash
# Start run_round2_rerun.sh detached from the host bridge, return at once.
H="$(cd "$(dirname "$0")" && pwd)"
nohup perl -e 'use POSIX qw(setsid); setsid(); exec @ARGV' /bin/bash "$H/run_round2_rerun.sh" "$@" \
  > "$H/run_round2_rerun.out" 2>&1 < /dev/null &
echo "rerun launched pid $!"
