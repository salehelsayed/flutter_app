#!/bin/bash
# Start build_r2fix.sh detached from the host bridge; return at once.
H="$(cd "$(dirname "$0")" && pwd)"
nohup perl -e 'use POSIX qw(setsid); setsid(); exec @ARGV' /bin/bash "$H/build_r2fix.sh" \
  > "$H/build_r2fix.out" 2>&1 < /dev/null &
echo "r2fix build launched pid $!"
