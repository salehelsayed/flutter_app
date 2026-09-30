#!/bin/bash
# Start build_round2.sh detached from the host bridge; return at once.
H="$(cd "$(dirname "$0")" && pwd)"
nohup perl -e 'use POSIX qw(setsid); setsid(); exec @ARGV' /bin/bash "$H/build_round2.sh" \
  > "$H/build_round2.out" 2>&1 < /dev/null &
echo "round2 build launched pid $!"
